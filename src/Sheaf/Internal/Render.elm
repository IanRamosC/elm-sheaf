module Sheaf.Internal.Render exposing (render)

{-| Building a whole site from the host's request.

It takes the request as JSON, so that tests drive it exactly as the host does.

@docs render

-}

import Dict exposing (Dict)
import Json.Decode as Decode
import Sheaf.Html exposing (Html)
import Sheaf.Internal.Date as Date
import Sheaf.Internal.Frontmatter as Frontmatter
import Sheaf.Internal.Head as Head
import Sheaf.Internal.Hint as Hint
import Sheaf.Internal.Html as Html exposing (HtmlProblem(..), Url(..))
import Sheaf.Internal.Markdown as Markdown
import Sheaf.Internal.Path as Path
import Sheaf.Internal.Pattern as Pattern
import Sheaf.Internal.Protocol as Protocol exposing (Diagnostic, Document, Request, Response, Severity(..))
import Sheaf.Internal.Site exposing (FrontmatterProblems, Item, Page, Route(..), Site(..))
import Sheaf.Ref as Ref exposing (Ref)


{-| Every page of the site, and every problem found while building it.

A page with a problem is not written, but the rest of the site still is, so
one build reports as many problems as it can.

-}
render : Site -> Decode.Value -> Response
render ((Site { metadata }) as site) json =
    case Decode.decodeValue Protocol.requestDecoder json of
        Ok request ->
            renderSite site request

        Err problem ->
            { site = metadata
            , pages = []
            , feeds = []
            , sitemap = []
            , diagnostics =
                [ { severity = Error
                  , title = "BAD REQUEST"
                  , message = "The host sent a request this site cannot read:\n\n" ++ Decode.errorToString problem
                  , sourcePath = Nothing
                  , span = Nothing
                  , hint = Just "Check that the `elm-sheaf` npm package and the `ianramosc/elm-sheaf` Elm package are the same version."
                  }
                ]
            }


type alias Context =
    { origin : String
    , basePath : String
    , documents : Dict String Document

    -- The pattern of the first item route of each collection.
    , itemPatterns : Dict String String
    }


renderSite : Site -> Request -> Response
renderSite (Site site) request =
    let
        context : Context
        context =
            { origin = request.build.origin
            , basePath = request.build.basePath
            , documents = Dict.fromList (List.map (\document -> ( document.id, document )) request.documents)
            , itemPatterns =
                -- Reversed, because `Dict.fromList` keeps the last.
                site.routes
                    |> List.filterMap itemPattern
                    |> List.reverse
                    |> Dict.fromList
            }

        used : List String
        used =
            usedCollections site.routes

        published : List Document
        published =
            List.filter (\document -> not document.excluded && List.member document.collection used) request.documents

        bodies : List Body
        bodies =
            List.map (\document -> ( document, renderBody context document )) published

        made : List (Result (List Diagnostic) UncheckedPage)
        made =
            -- A bad route makes no pages; its error ends the build.
            site.routes
                |> List.indexedMap Tuple.pair
                |> List.filter (\( _, route ) -> routeProblem route == Nothing)
                |> List.concatMap (\( index, route ) -> pagesOf context bodies index route)

        ( written, duplicates ) =
            withoutDuplicates (List.filterMap Result.toMaybe made)

        checked : List CheckedPage
        checked =
            List.map (check context) written
    in
    { site = site.metadata
    , pages =
        checked
            |> List.filter (\page -> List.isEmpty page.brokenLinks && List.isEmpty page.problems)
            |> List.map (write context site.metadata.language)
    , feeds = []
    , sitemap = []
    , diagnostics =
        List.concat
            [ unique (List.filterMap badRoute site.routes)
            , unknownCollections used request.collections
            , missingDates (unique (List.filterMap listedCollection site.routes)) published
            , List.concatMap (Tuple.second >> errors) bodies

            -- Two routes over one collection decode its frontmatter twice.
            , unique (List.concatMap errors made)
            , List.map brokenLinkDiagnostic (groupBrokenLinks checked)
            , List.concatMap .problems checked
            , duplicates
            ]
    }


itemPattern : Route -> Maybe ( String, String )
itemPattern route =
    case route of
        EachItem item ->
            Just ( item.collection, item.pattern )

        Single _ ->
            Nothing

        NotFound _ ->
            Nothing

        Paginated _ ->
            Nothing

        AllItems _ ->
            Nothing


{-| The collection a route takes, if it takes one.
-}
collectionOf : Route -> Maybe String
collectionOf route =
    case route of
        Single _ ->
            Nothing

        NotFound _ ->
            Nothing

        EachItem item ->
            Just item.collection

        Paginated listing ->
            Just listing.collection

        AllItems listing ->
            Just listing.collection


{-| The collection a route lists by date, if it lists one.
-}
listedCollection : Route -> Maybe String
listedCollection route =
    case route of
        Paginated listing ->
            Just listing.collection

        AllItems listing ->
            Just listing.collection

        Single _ ->
            Nothing

        NotFound _ ->
            Nothing

        EachItem _ ->
            Nothing


{-| The collections the routes use, in the order they are first used.
-}
usedCollections : List Route -> List String
usedCollections routes =
    unique (List.filterMap collectionOf routes)


errors : Result (List e) a -> List e
errors result =
    case result of
        Ok _ ->
            []

        Err problems ->
            problems


{-| The first of each item, in order.
-}
unique : List a -> List a
unique =
    List.foldl
        (\item kept ->
            if List.member item kept then
                kept

            else
                kept ++ [ item ]
        )
        []



-- ROUTES


{-| How a route is named in messages: by its pattern, or by the function that
makes the one route without a pattern.
-}
nameOf : Route -> String
nameOf route =
    case patternOf route of
        Just ( _, pattern ) ->
            pattern

        Nothing ->
            "Route.notFound"


patternOf : Route -> Maybe ( Pattern.Kind, String )
patternOf route =
    case route of
        Single single ->
            Just ( Pattern.Fixed, single.pattern )

        NotFound _ ->
            Nothing

        EachItem item ->
            Just ( Pattern.Item, item.pattern )

        Paginated listing ->
            Just ( Pattern.Listing, listing.pattern )

        AllItems listing ->
            Just ( Pattern.Fixed, listing.pattern )


type RouteProblem
    = BadPattern Pattern.Problem
    | TooFewPerPage Int


routeProblem : Route -> Maybe RouteProblem
routeProblem route =
    case Maybe.andThen (\( kind, pattern ) -> Pattern.problem kind pattern) (patternOf route) of
        Just problem ->
            Just (BadPattern problem)

        Nothing ->
            case route of
                Paginated listing ->
                    -- Cutting a list into pieces of none never ends, and the
                    -- host cannot stop the worker while it runs.
                    if listing.perPage < 1 then
                        Just (TooFewPerPage listing.perPage)

                    else
                        Nothing

                Single _ ->
                    Nothing

                NotFound _ ->
                    Nothing

                EachItem _ ->
                    Nothing

                AllItems _ ->
                    Nothing


badRoute : Route -> Maybe Diagnostic
badRoute route =
    let
        diagnostic : String -> Maybe String -> Diagnostic
        diagnostic problem hint =
            { severity = Error
            , title = "BAD ROUTE"
            , message = "The route `" ++ nameOf route ++ "` " ++ problem ++ ", so its pages could not be written."
            , sourcePath = Nothing
            , span = Nothing
            , hint = hint
            }
    in
    routeProblem route
        |> Maybe.map
            (\problem ->
                let
                    shapeHint : Maybe String
                    shapeHint =
                        Just "A pattern starts with `/` and separates its segments with single slashes, as in `/posts/:slug/` or `/humans.txt`."
                in
                case problem of
                    BadPattern Pattern.NoLeadingSlash ->
                        diagnostic "does not start with `/`" shapeHint

                    BadPattern Pattern.QueryOrFragment ->
                        diagnostic "contains `?` or `#`, which would start a query or a fragment" shapeHint

                    BadPattern Pattern.EmptySegment ->
                        diagnostic "has an empty segment" shapeHint

                    BadPattern (Pattern.DotSegment segment) ->
                        diagnostic ("has a `" ++ segment ++ "` segment") shapeHint

                    BadPattern (Pattern.UnknownPlaceholder placeholder) ->
                        diagnostic ("has the placeholder `" ++ placeholder ++ "`, which this kind of route does not fill")
                            (Just "Only `Route.eachItem` fills a placeholder, `:slug`, and a placeholder is a whole segment, as in `/posts/:slug/`.")

                    BadPattern (Pattern.MissingPlaceholder Pattern.Slug) ->
                        diagnostic "does not have the placeholder `:slug`, which gives each document its own page"
                            (Just "Put `:slug` in a segment of its own, as in `/posts/:slug/`.")

                    BadPattern Pattern.NotAFolder ->
                        diagnostic "does not end with `/`, but its later pages are written under it"
                            (Just "End the pattern with `/`, as in `/archive/`. Its second page is then `/archive/page/2/`.")

                    TooFewPerPage perPage ->
                        diagnostic ("has `perPage = " ++ String.fromInt perPage ++ "`, but `perPage` must be at least 1") Nothing
            )



-- COLLECTIONS


unknownCollections : List String -> List String -> List Diagnostic
unknownCollections declared folders =
    List.map (declaredWithoutFolder folders) (List.filter (\name -> not (List.member name folders)) declared)
        ++ List.map (folderWithoutRoute declared) (List.filter (\name -> not (List.member name declared)) folders)


declaredWithoutFolder : List String -> String -> Diagnostic
declaredWithoutFolder folders name =
    { severity = Error
    , title = "UNKNOWN COLLECTION"
    , message = "A route uses `Collection.named \"" ++ name ++ "\"`, but there is no `content/" ++ name ++ "` folder."
    , sourcePath = Nothing
    , span = Nothing
    , hint =
        Hint.didYouMean (\names -> "The folders in `content/` are " ++ names ++ ".") folders name
            |> Maybe.map (\suggestion -> suggestion ++ "\n\n" ++ emptyFolderHint name)
            |> Maybe.withDefault (emptyFolderHint name)
            |> Just
    }


{-| An empty collection is a real case, and Git silently drops its folder.
-}
emptyFolderHint : String -> String
emptyFolderHint name =
    "Git does not keep empty folders: add an empty `content/" ++ name ++ "/.gitkeep` file and commit it."


folderWithoutRoute : List String -> String -> Diagnostic
folderWithoutRoute declared name =
    { severity = Error
    , title = "UNKNOWN COLLECTION"
    , message = "The folder `content/" ++ name ++ "` is a collection, but no route uses `Collection.named \"" ++ name ++ "\"`."
    , sourcePath = Nothing
    , span = Nothing
    , hint = Hint.didYouMean (\names -> "The routes use " ++ names ++ ".") declared name
    }



-- DATES


{-| A listing orders its documents by date, so each needs one. A document is
reported once, however many routes list its collection.
-}
missingDates : List String -> List Document -> List Diagnostic
missingDates listed published =
    published
        |> List.filter (\document -> document.date == Nothing && List.member document.collection listed)
        |> List.map
            (\document ->
                { severity = Error
                , title = "MISSING DATE"
                , message = "This document has no date, but `" ++ document.collection ++ "` is listed by date."
                , sourcePath = Just document.sourcePath
                , span = Maybe.map .value (Dict.get "" document.frontmatterPositions)
                , hint = Just "Add `date: YYYY-MM-DD` to its frontmatter, or start its file name with the date."
                }
            )


{-| Newest first, and documents of the same date by slug, so that a listing
does not change from one build to the next.
-}
newestFirst : Document -> Document -> Order
newestFirst a b =
    case ( a.date, b.date ) of
        ( Just dateA, Just dateB ) ->
            case Date.compareNewestFirst (Date.fromProtocol dateA) (Date.fromProtocol dateB) of
                EQ ->
                    compare a.slug b.slug

                order ->
                    order

        -- A listing with an undated document is not written, but it is
        -- still put in order to check every document's frontmatter.
        ( Just _, Nothing ) ->
            LT

        ( Nothing, Just _ ) ->
            GT

        ( Nothing, Nothing ) ->
            compare a.slug b.slug



-- LINKS


type LinkProblem
    = ToDraft
    | ToCollectionWithoutPages String
    | ToNothing


linkTarget : Context -> Ref -> Result LinkProblem String
linkTarget context ref =
    case Dict.get (Ref.id ref) context.documents of
        Nothing ->
            Err ToNothing

        Just document ->
            if document.excluded then
                Err ToDraft

            else
                case Dict.get document.collection context.itemPatterns of
                    Just pattern ->
                        Ok (Path.join context.basePath (Pattern.fill Pattern.Slug document.slug pattern))

                    Nothing ->
                        Err (ToCollectionWithoutPages document.collection)


{-| Where a URL left to the renderer points. A site path that is not valid is
reported by `Html.problems`, and its page is not written.
-}
urlTarget : Context -> Url -> Maybe String
urlTarget context url =
    case url of
        DocumentUrl ref ->
            Result.toMaybe (linkTarget context ref)

        SitePath path ->
            Just (Path.join context.basePath path)


{-| A diagnostic for a link, given where it was written: the start of its
message, and the source path and span when it was written in Markdown.
-}
linkDiagnostic : { subject : String, sourcePath : Maybe String, span : Maybe Protocol.Span } -> Ref -> LinkProblem -> Diagnostic
linkDiagnostic origin ref problem =
    let
        target : String
        target =
            origin.subject ++ " `" ++ Ref.id ref ++ "`"

        located : String -> String -> Maybe String -> Diagnostic
        located title message hint =
            { severity = Error
            , title = title
            , message = message
            , sourcePath = origin.sourcePath
            , span = origin.span
            , hint = hint
            }
    in
    case problem of
        ToDraft ->
            located "LINK TO DRAFT"
                (target ++ ", which is not published in this build because it is a draft or dated in the future.")
                (Just "Publish it, or remove the link. Drafts and future-dated documents are only built by `sheaf dev` and `sheaf build --drafts`.")

        ToCollectionWithoutPages collection ->
            located "NO PAGE FOR LINK"
                (target ++ ", but no route gives the documents of `" ++ collection ++ "` a page.")
                (Just ("Add a `Route.eachItem` route for the `" ++ collection ++ "` collection."))

        ToNothing ->
            located "BROKEN LINK" (target ++ ", but there is no such document.") Nothing



-- BODIES


{-| A document's Markdown, rendered once however many routes use it.
-}
renderBody : Context -> Document -> Result (List Diagnostic) (List Html)
renderBody context document =
    Markdown.render (linkTarget context >> Result.toMaybe) (Markdown.fromNode document.tree)
        |> Result.mapError
            (List.filterMap
                (\problem ->
                    let
                        ref : Ref
                        ref =
                            Ref.fromId problem.id
                    in
                    linkTarget context ref
                        |> errorOf
                        |> Maybe.map
                            (linkDiagnostic
                                { subject = "This document links to"
                                , sourcePath = Just document.sourcePath
                                , span = Just problem.span
                                }
                                ref
                            )
                )
            )


errorOf : Result e a -> Maybe e
errorOf result =
    case result of
        Ok _ ->
            Nothing

        Err problem ->
            Just problem



-- PAGES


{-| A published document and its rendered body, or the problems of its body.
-}
type alias Body =
    ( Document, Result (List Diagnostic) (List Html) )


{-| Where a page is served. The 404 page is served in place of any missing
page, so it has no URL of its own.
-}
type Location
    = At String
    | InPlaceOfMissingPages


{-| The URL a page is written at, and named by in messages.
-}
urlOf : Location -> String
urlOf location =
    case location of
        At url ->
            url

        InPlaceOfMissingPages ->
            "/404.html"


{-| A page a route made, before its links are resolved and it is checked.

`route` is the route's place in the site's list, because two routes can have
the same pattern.

-}
type alias UncheckedPage =
    { route : Int
    , routeName : String
    , location : Location
    , page : Page
    }


{-| The pages a route makes. A document whose body has problems (reported
once, by `renderSite`) gets no page, but its frontmatter is still checked.
-}
pagesOf : Context -> List Body -> Int -> Route -> List (Result (List Diagnostic) UncheckedPage)
pagesOf context bodies index route =
    let
        madeAt : String -> Page -> UncheckedPage
        madeAt url page =
            { route = index, routeName = nameOf route, location = At url, page = page }
    in
    case route of
        Single single ->
            [ Ok (madeAt single.pattern single.page) ]

        NotFound page ->
            [ Ok { route = index, routeName = nameOf route, location = InPlaceOfMissingPages, page = page } ]

        EachItem item ->
            bodies
                |> List.filter (\( document, _ ) -> document.collection == item.collection)
                |> List.filterMap
                    (\( document, body ) ->
                        case ( item.templateFor document, body ) of
                            ( Ok template, Ok html ) ->
                                Just (Ok (madeAt (Pattern.fill Pattern.Slug document.slug item.pattern) (template html)))

                            ( Err problems, _ ) ->
                                Just (Err (List.map (frontmatterDiagnostic document) problems))

                            ( Ok _, Err _ ) ->
                                Nothing
                    )

        Paginated listing ->
            let
                ( items, complete ) =
                    listOf listing.collection bodies

                chunks : List (List Item)
                chunks =
                    chunksOf listing.perPage items

                pages : Int
                pages =
                    List.length chunks

                linkTo : Int -> Maybe String
                linkTo n =
                    if n >= 1 && n <= pages then
                        Just (Path.join context.basePath (Pattern.pageOf n listing.pattern))

                    else
                        Nothing
            in
            chunks
                |> List.indexedMap
                    (\i chunk ->
                        let
                            n : Int
                            n =
                                i + 1
                        in
                        listing.templateFor { page = n, pages = pages, previous = linkTo (n - 1), next = linkTo (n + 1) } chunk
                            |> Result.map (madeAt (Pattern.pageOf n listing.pattern))
                    )
                |> whole complete

        AllItems listing ->
            let
                ( items, complete ) =
                    listOf listing.collection bodies
            in
            [ Result.map (madeAt listing.pattern) (listing.templateFor items) ]
                |> whole complete


{-| The published documents of a collection, newest first, and whether every
one of them can be listed: one without a date, or whose body has problems,
would leave a hole in the listing. Their problems are reported on their own,
and the frontmatter of each is still checked, so a body with problems is
given as empty.
-}
listOf : String -> List Body -> ( List Item, Bool )
listOf collection bodies =
    let
        listed : List Body
        listed =
            bodies
                |> List.filter (\( document, _ ) -> document.collection == collection)
                |> List.sortWith (\( a, _ ) ( b, _ ) -> newestFirst a b)
    in
    ( List.map (\( document, body ) -> { document = document, body = Result.withDefault [] body }) listed
    , List.all (\( document, body ) -> document.date /= Nothing && List.isEmpty (errors body)) listed
    )


{-| A listing is written whole or not at all, since a missing document or
page would go unnoticed. The frontmatter problems of its documents are
reported either way.
-}
whole : Bool -> List (Result (List FrontmatterProblems) UncheckedPage) -> List (Result (List Diagnostic) UncheckedPage)
whole complete made =
    case List.concatMap errors made of
        [] ->
            if complete then
                List.map Ok (List.filterMap Result.toMaybe made)

            else
                []

        invalid ->
            [ Err (List.concatMap (\{ document, problems } -> List.map (frontmatterDiagnostic document) problems) invalid) ]


{-| At least one chunk, so that an empty listing still has its first page.
-}
chunksOf : Int -> List a -> List (List a)
chunksOf size items =
    case List.drop size items of
        [] ->
            [ List.take size items ]

        rest ->
            List.take size items :: chunksOf size rest


frontmatterDiagnostic : Document -> Frontmatter.Problem -> Diagnostic
frontmatterDiagnostic document problem =
    { severity = Error
    , title = problem.title
    , message = problem.message
    , sourcePath = Just document.sourcePath
    , span = problem.span
    , hint = problem.hint
    }


{-| A pattern ending in `/` is a folder, written as its `index.html`.
-}
pathOf : Location -> String
pathOf location =
    let
        relative : String
        relative =
            Path.dropLeadingSlash (urlOf location)
    in
    if relative == "" || String.endsWith "/" relative then
        relative ++ "index.html"

    else
        relative


{-| The first page at each path, and a diagnostic for every later one.
-}
withoutDuplicates : List UncheckedPage -> ( List UncheckedPage, List Diagnostic )
withoutDuplicates pages =
    let
        step : UncheckedPage -> ( Dict String UncheckedPage, List UncheckedPage, List Diagnostic ) -> ( Dict String UncheckedPage, List UncheckedPage, List Diagnostic )
        step page ( seen, kept, duplicates ) =
            let
                path : String
                path =
                    pathOf page.location
            in
            case Dict.get path seen of
                Just first ->
                    ( seen, kept, duplicate path first page :: duplicates )

                Nothing ->
                    ( Dict.insert path page seen, page :: kept, duplicates )

        ( _, written, found ) =
            List.foldl step ( Dict.empty, [], [] ) pages
    in
    -- A third route with the same pattern as the second repeats its message.
    ( List.reverse written, unique (List.reverse found) )


duplicate : String -> UncheckedPage -> UncheckedPage -> Diagnostic
duplicate path first second =
    { severity = Error
    , title = "DUPLICATE PAGE"
    , message = "The routes `" ++ first.routeName ++ "` and `" ++ second.routeName ++ "` both make the page `" ++ path ++ "`."
    , sourcePath = Nothing
    , span = Nothing
    , hint = Nothing
    }



-- CHECKING


{-| A page with the problems found in it. Its broken links are reported
together with the same ones on other pages of its route, since they usually
come from a layout they share.
-}
type alias CheckedPage =
    { unchecked : UncheckedPage
    , head : List Html
    , brokenLinks : List ( Ref, LinkProblem )
    , problems : List Diagnostic
    }


check : Context -> UncheckedPage -> CheckedPage
check context unchecked =
    let
        page : Page
        page =
            unchecked.page

        subject : String
        subject =
            "While rendering `" ++ urlOf unchecked.location ++ "` from the route `" ++ unchecked.routeName ++ "`,"

        ownUrl : Maybe String
        ownUrl =
            case unchecked.location of
                At url ->
                    Just url

                InPlaceOfMissingPages ->
                    Nothing

        head : List Html
        head =
            Html.node "title" [] [ Html.text page.title ]
                :: List.concatMap (Head.toHtml { origin = context.origin, basePath = context.basePath, url = ownUrl }) page.head
    in
    { unchecked = unchecked
    , head = head
    , brokenLinks =
        page.body
            |> List.concatMap Html.urls
            |> List.filterMap
                (\target ->
                    case target of
                        DocumentUrl ref ->
                            linkTarget context ref
                                |> errorOf
                                |> Maybe.map (Tuple.pair ref)

                        SitePath _ ->
                            Nothing
                )
            |> unique

    -- Checked before resolving, which would hide a bad site path.
    , problems =
        List.map (invalidHtml subject) (List.concatMap Html.problems (head ++ page.body))
            ++ List.map (invalidHeadPath subject) (List.concatMap Head.problems page.head)
    }


{-| Resolve a page's URLs and render it.
-}
write : Context -> String -> CheckedPage -> Protocol.Page
write context language { unchecked, head } =
    { path = pathOf unchecked.location
    , html =
        Html.document
            { lang = language
            , head = head
            , body = List.map (Html.resolveUrls (urlTarget context)) unchecked.page.body
            }
    }


{-| The same broken link on the pages of one route.
-}
type alias BrokenLink =
    { route : Int
    , routeName : String
    , ref : Ref
    , problem : LinkProblem
    , firstUrl : String
    , pages : Int
    }


groupBrokenLinks : List CheckedPage -> List BrokenLink
groupBrokenLinks pages =
    List.foldl
        (\{ unchecked, brokenLinks } found -> List.foldl (addBrokenLink unchecked) found brokenLinks)
        []
        pages


addBrokenLink : UncheckedPage -> ( Ref, LinkProblem ) -> List BrokenLink -> List BrokenLink
addBrokenLink page ( ref, problem ) found =
    let
        isSame : BrokenLink -> Bool
        isSame link =
            link.route == page.route && link.ref == ref && link.problem == problem
    in
    if List.any isSame found then
        List.map
            (\link ->
                if isSame link then
                    { link | pages = link.pages + 1 }

                else
                    link
            )
            found

    else
        found ++ [ { route = page.route, routeName = page.routeName, ref = ref, problem = problem, firstUrl = urlOf page.location, pages = 1 } ]


brokenLinkDiagnostic : BrokenLink -> Diagnostic
brokenLinkDiagnostic link =
    let
        subject : String
        subject =
            if link.pages == 1 then
                "While rendering `" ++ link.firstUrl ++ "` from the route `" ++ link.routeName ++ "`,"

            else
                "While rendering "
                    ++ String.fromInt link.pages
                    ++ " pages from the route `"
                    ++ link.routeName
                    ++ "` (the first is `"
                    ++ link.firstUrl
                    ++ "`),"
    in
    linkDiagnostic
        { subject = subject ++ " a `Sheaf.link` points to"
        , sourcePath = Nothing
        , span = Nothing
        }
        link.ref
        link.problem


invalidHtml : String -> HtmlProblem -> Diagnostic
invalidHtml subject problem =
    let
        diagnostic : String -> Maybe String -> Diagnostic
        diagnostic message hint =
            { severity = Error
            , title = "INVALID HTML"
            , message = subject ++ " the template " ++ message
            , sourcePath = Nothing
            , span = Nothing
            , hint = hint
            }
    in
    case problem of
        InvalidTagName tag ->
            diagnostic ("made an element named `" ++ tag ++ "`, which is not a valid tag name.") Nothing

        InvalidAttributeName { tag, name } ->
            diagnostic ("gave a `<" ++ tag ++ ">` element an attribute named `" ++ name ++ "`, which is not a valid attribute name.") Nothing

        RawTextElement tag ->
            diagnostic ("made a `<" ++ tag ++ ">` element, whose content cannot be escaped.")
                (Just "Put styles and scripts in files under `static/` and link to them instead.")

        InvalidSitePath { tag, name, path } ->
            diagnostic ("gave a `<" ++ tag ++ ">` element the site path `" ++ path ++ "` for its `" ++ name ++ "`, but a site path starts with a single `/`.")
                (Just "Write a site path from the root of the site, such as `/archive/`. The base path is added for you. For a URL on another host, use `href` or `src`.")


invalidHeadPath : String -> Head.PathProblem -> Diagnostic
invalidHeadPath subject { function, path } =
    { severity = Error
    , title = "INVALID HTML"
    , message =
        subject
            ++ " the template gave `"
            ++ function
            ++ "` the path `"
            ++ path
            ++ "`, but a path in the head is either a site path, which starts with a single `/`, or a full `http://` or `https://` URL."
    , sourcePath = Nothing
    , span = Nothing
    , hint = Just "Write a site path from the root of the site, such as `/style.css`. The base path is added for you."
    }
