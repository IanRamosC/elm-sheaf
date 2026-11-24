module Sheaf.Internal.Render exposing (render)

{-| Building a whole site from the host's request.

It takes the request as JSON, so that tests drive it exactly as the host does.

@docs render

-}

import Dict exposing (Dict)
import Json.Decode as Decode
import Set exposing (Set)
import Sheaf.Html exposing (Html)
import Sheaf.Internal.Check as Check exposing (CheckedPage, GroupLinkProblem(..), LinkProblem(..), Location(..), UncheckedPage)
import Sheaf.Internal.Group as Group exposing (Group)
import Sheaf.Internal.Hint as Hint
import Sheaf.Internal.Html as Html exposing (GroupLink, Url(..))
import Sheaf.Internal.Listing as Listing exposing (Body)
import Sheaf.Internal.Markdown as Markdown
import Sheaf.Internal.Path as Path
import Sheaf.Internal.Pattern as Pattern
import Sheaf.Internal.Protocol as Protocol exposing (Diagnostic, Document, GroupSlug, Request, Response, Severity(..))
import Sheaf.Internal.RouteCheck as RouteCheck
import Sheaf.Internal.Site as Site exposing (FrontmatterProblems, Grouping, ListedDocument, Page, Route(..), Site(..))
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
    , slugs : Dict String GroupSlug
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
                    |> List.filterMap Site.itemPattern
                    |> List.reverse
                    |> Dict.fromList
            , slugs = request.slugs
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

        -- A bad route makes no pages; its error ends the build.
        goodRoutes : List ( Int, Route )
        goodRoutes =
            site.routes
                |> List.indexedMap Tuple.pair
                |> List.filter (\( _, route ) -> RouteCheck.badRoute route == Nothing)

        made : List (Result (List Diagnostic) UncheckedPage)
        made =
            List.concatMap (\( index, route ) -> pagesOf context bodies index route) goodRoutes

        ( written, duplicates ) =
            withoutDuplicates (List.filterMap Result.toMaybe made)

        groupPages : Dict String (Set String)
        groupPages =
            groupPagesOf context bodies (List.map Tuple.second goodRoutes)

        checked : List CheckedPage
        checked =
            List.map
                (Check.check
                    { origin = context.origin
                    , basePath = context.basePath
                    , linkProblem = linkTarget context >> errorOf
                    , groupLinkProblem = groupLinkTarget context groupPages >> errorOf
                    }
                )
                written
    in
    { site = site.metadata
    , pages =
        checked
            |> List.filter (\page -> List.isEmpty page.brokenLinks && List.isEmpty page.problems)
            |> List.map (write (urlTarget context groupPages) site.metadata.language)
    , feeds = []
    , sitemap = []
    , diagnostics =
        List.concat
            [ unique (List.filterMap RouteCheck.badRoute site.routes)
            , unknownCollections used request.collections
            , Listing.missingDates (unique (List.filterMap Site.listedCollection site.routes)) published
            , List.concatMap (Tuple.second >> errors) bodies
            , groupProblems context bodies (List.map Tuple.second goodRoutes)

            -- Two routes over one collection decode its frontmatter twice.
            , unique (List.concatMap errors made)
            , Check.brokenLinkDiagnostics checked
            , List.concatMap .problems checked
            , duplicates
            ]
    }


{-| The collections the routes use, in the order they are first used.
-}
usedCollections : List Route -> List String
usedCollections routes =
    unique (List.filterMap Site.collectionOf routes)


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



-- LINKS


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


{-| Where a link to a group points: the group's page of the first `groupedBy`
route with the link's pattern, given the slugs of the groups it has pages for.
-}
groupLinkTarget : Context -> Dict String (Set String) -> GroupLink -> Result GroupLinkProblem String
groupLinkTarget context groupPages link =
    case ( Dict.get link.pattern groupPages, Dict.get link.value context.slugs ) of
        ( Nothing, _ ) ->
            Err (NoGroupedRoute (Dict.keys groupPages))

        ( Just _, Nothing ) ->
            Err ValueWithoutSlug

        ( Just slugs, Just { slug } ) ->
            if Set.member slug slugs then
                Ok (Path.join context.basePath (Pattern.fill Pattern.Group slug link.pattern))

            else
                Err EmptyGroup


{-| Where a URL left to the renderer points. A site path that is not valid is
reported by `Html.problems`, and its page is not written.
-}
urlTarget : Context -> Dict String (Set String) -> Url -> Maybe String
urlTarget context groupPages url =
    case url of
        DocumentUrl ref ->
            Result.toMaybe (linkTarget context ref)

        GroupUrl link ->
            Result.toMaybe (groupLinkTarget context groupPages link)

        SitePath path ->
            Just (Path.join context.basePath path)



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
                            (Check.linkDiagnostic
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


{-| The pages a route makes. A document whose body has problems (reported
once, by `renderSite`) gets no page, but its frontmatter is still checked.
-}
pagesOf : Context -> List Body -> Int -> Route -> List (Result (List Diagnostic) UncheckedPage)
pagesOf context bodies index route =
    let
        madeAt : String -> Page -> UncheckedPage
        madeAt url page =
            { route = index, routeName = Site.nameOf route, location = At url, page = page }
    in
    case route of
        Single single ->
            [ Ok (madeAt single.pattern single.page) ]

        NotFound page ->
            [ Ok { route = index, routeName = Site.nameOf route, location = InPlaceOfMissingPages, page = page } ]

        EachItem item ->
            bodies
                |> List.filter (\( document, _ ) -> document.collection == item.collection)
                |> List.filterMap
                    (\( document, body ) ->
                        case ( item.templateFor document, body ) of
                            ( Ok template, Ok html ) ->
                                Just (Ok (madeAt (Pattern.fill Pattern.Slug document.slug item.pattern) (template html)))

                            ( Err problems, _ ) ->
                                Just (Err (List.map (Listing.frontmatterDiagnostic document) problems))

                            ( Ok _, Err _ ) ->
                                Nothing
                    )

        Paginated listing ->
            let
                ( items, complete ) =
                    Listing.listOf listing.collection bodies
            in
            Listing.paginate { basePath = context.basePath, pattern = listing.pattern, perPage = listing.perPage } items
                |> List.map (\page -> Result.map (madeAt page.url) (listing.templateFor page.pagination page.items))
                |> Listing.whole complete

        AllItems listing ->
            let
                ( items, complete ) =
                    Listing.listOf listing.collection bodies
            in
            [ Result.map (madeAt listing.pattern) (listing.templateFor items) ]
                |> Listing.whole complete

        GroupedBy grouped ->
            let
                grouping : Grouped
                grouping =
                    groupedDocuments context bodies grouped.grouping
            in
            grouping.groups
                |> List.concatMap
                    (\group ->
                        Listing.paginate
                            { basePath = context.basePath
                            , pattern = Pattern.fill Pattern.Group group.slug grouped.pattern

                            -- A group has at least one document, so its one page is never cut into pieces of none.
                            , perPage = Maybe.withDefault (List.length group.items) grouped.perPage
                            }
                            group.items
                            |> List.map (\page -> Result.map (madeAt page.url) (grouped.templateFor group.name page.pagination page.items))
                    )
                |> wholeGrouping grouping

        AllGroups all ->
            let
                grouping : Grouped
                grouping =
                    groupedDocuments context bodies all.grouping
            in
            [ Result.map (madeAt all.pattern) (all.templateFor (List.map (\group -> { name = group.name, items = group.items }) grouping.groups)) ]
                |> wholeGrouping grouping



-- GROUPS


{-| The groups of a grouping route's documents, and what keeps it from being
written: as for a listing, a document that cannot be listed, a frontmatter
that does not decode, or a value that cannot be grouped.
-}
type alias Grouped =
    { groups : List (Group ListedDocument)
    , problems : List Group.Problem
    , complete : Bool
    , invalid : List FrontmatterProblems
    }


groupedDocuments : Context -> List Body -> Grouping -> Grouped
groupedDocuments context bodies grouping =
    let
        ( items, complete ) =
            Listing.listOf grouping.collection bodies

        ( valued, invalid ) =
            List.foldr
                (\item ( ok, failed ) ->
                    case grouping.valuesOf item.document of
                        Ok values ->
                            ( ( item, values ) :: ok, failed )

                        Err frontmatterProblems ->
                            ( ok, { document = item.document, problems = frontmatterProblems } :: failed )
                )
                ( [], [] )
                items

        { groups, problems } =
            Group.group context.slugs valued
    in
    { groups = groups, problems = problems, complete = complete, invalid = invalid }


{-| A grouping route's problems with values are reported by `groupProblems`,
once for all the routes that find them.
-}
wholeGrouping : Grouped -> List (Result (List FrontmatterProblems) UncheckedPage) -> List (Result (List Diagnostic) UncheckedPage)
wholeGrouping grouping pages =
    let
        undecoded : List (Result (List FrontmatterProblems) UncheckedPage)
        undecoded =
            if List.isEmpty grouping.invalid then
                []

            else
                [ Err grouping.invalid ]
    in
    Listing.whole (grouping.complete && List.isEmpty grouping.problems) (undecoded ++ pages)


{-| The problems of the values routes group by. Routes grouping the same
documents by the same values find the same problems, so each is reported once,
naming the first route that found it.
-}
groupProblems : Context -> List Body -> List Route -> List Diagnostic
groupProblems context bodies routes =
    routes
        |> List.concatMap
            (\route ->
                case Site.groupingOf route of
                    Just grouping ->
                        List.map (Tuple.pair (Site.nameOf route)) (groupedDocuments context bodies grouping).problems

                    Nothing ->
                        []
            )
        |> List.foldl
            (\( routeName, problem ) found ->
                if List.any (\( _, seen ) -> seen == problem) found then
                    found

                else
                    found ++ [ ( routeName, problem ) ]
            )
            []
        |> List.map (\( routeName, problem ) -> Group.diagnostic routeName problem)


{-| The slugs of the groups each `groupedBy` pattern has pages for, from the
first route with that pattern, as links to groups use.
-}
groupPagesOf : Context -> List Body -> List Route -> Dict String (Set String)
groupPagesOf context bodies routes =
    routes
        |> List.filterMap Site.groupedPattern
        |> List.map (\( pattern, grouping ) -> ( pattern, Set.fromList (List.map .slug (groupedDocuments context bodies grouping).groups) ))
        -- Reversed, because `Dict.fromList` keeps the last.
        |> List.reverse
        |> Dict.fromList


{-| A pattern ending in `/` is a folder, written as its `index.html`.
-}
pathOf : Location -> String
pathOf location =
    let
        relative : String
        relative =
            Path.dropLeadingSlash (Check.urlOf location)
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


{-| Resolve a page's URLs and render it.
-}
write : (Url -> Maybe String) -> String -> CheckedPage -> Protocol.Page
write resolve language { unchecked, head } =
    { path = pathOf unchecked.location
    , html =
        Html.document
            { lang = language
            , head = head
            , body = List.map (Html.resolveUrls resolve) unchecked.page.body
            }
    }
