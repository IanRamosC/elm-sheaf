module Sheaf.Internal.Render exposing (render)

{-| Building a whole site from the host's request.

It takes the request as JSON, so that tests drive it exactly as the host does.

@docs render

-}

import Dict exposing (Dict)
import Json.Decode as Decode
import Sheaf.Html exposing (Html)
import Sheaf.Internal.Frontmatter as Frontmatter
import Sheaf.Internal.Hint as Hint
import Sheaf.Internal.Html as Html exposing (HtmlProblem(..))
import Sheaf.Internal.Markdown as Markdown
import Sheaf.Internal.Protocol as Protocol exposing (Diagnostic, Document, Request, Response, Severity(..))
import Sheaf.Internal.Site exposing (Page, Route(..), Site(..))
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
    { basePath : String
    , documents : Dict String Document

    -- The pattern of the first item route of each collection.
    , itemPatterns : Dict String String
    }


renderSite : Site -> Request -> Response
renderSite (Site site) request =
    let
        context : Context
        context =
            { basePath = request.build.basePath
            , documents = Dict.fromList (List.map (\document -> ( document.id, document )) request.documents)
            , itemPatterns =
                -- Reversed, because `Dict.fromList` keeps the last.
                site.routes
                    |> List.filterMap itemPattern
                    |> List.reverse
                    |> Dict.fromList
            }

        bodies : List ( Document, Result (List Diagnostic) (List Html) )
        bodies =
            request.documents
                |> List.filter (\document -> not document.excluded && Dict.member document.collection context.itemPatterns)
                |> List.map (\document -> ( document, renderBody context document ))

        made : List (Result (List Diagnostic) UncheckedPage)
        made =
            -- A route with a bad pattern makes no pages; its error ends the build.
            site.routes
                |> List.indexedMap Tuple.pair
                |> List.filter (\( _, route ) -> patternProblem (patternOf route) == Nothing)
                |> List.concatMap (\( index, route ) -> pagesOf bodies index route)

        ( written, duplicates ) =
            withoutDuplicates (List.filterMap Result.toMaybe made)

        finished : List (Result (List Diagnostic) Protocol.Page)
        finished =
            List.map (finish context site.metadata.language) written
    in
    { site = site.metadata
    , pages = List.filterMap Result.toMaybe finished
    , feeds = []
    , sitemap = []
    , diagnostics =
        List.concat
            [ unique (List.filterMap badRoute site.routes)
            , unknownCollections (usedCollections site.routes) request.collections
            , List.concatMap (Tuple.second >> errors) bodies

            -- Two routes over one collection decode its frontmatter twice.
            , unique (List.concatMap errors made)
            , List.concatMap errors finished
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


patternOf : Route -> String
patternOf route =
    case route of
        EachItem item ->
            item.pattern

        Single single ->
            single.pattern


{-| The collections the routes use, in the order they are first used.
-}
usedCollections : List Route -> List String
usedCollections routes =
    routes
        |> List.filterMap (itemPattern >> Maybe.map Tuple.first)
        |> unique


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


{-| Why a pattern cannot be turned into a file path inside the output folder,
or a URL that leads back to it.
-}
type PatternProblem
    = NoLeadingSlash
    | QueryOrFragment
    | EmptySegment
    | DotSegment String


patternProblem : String -> Maybe PatternProblem
patternProblem pattern =
    if not (String.startsWith "/" pattern) then
        Just NoLeadingSlash

    else if String.contains "?" pattern || String.contains "#" pattern then
        Just QueryOrFragment

    else if pattern == "/" then
        Nothing

    else
        -- A trailing `/` makes the pattern a folder, so its empty last
        -- segment is allowed.
        segmentProblem (String.split "/" (dropTrailingSlash (String.dropLeft 1 pattern)))


segmentProblem : List String -> Maybe PatternProblem
segmentProblem segments =
    if List.member "" segments then
        Just EmptySegment

    else
        segments
            |> List.filter (\segment -> segment == "." || segment == "..")
            |> List.head
            |> Maybe.map DotSegment


badRoute : Route -> Maybe Diagnostic
badRoute route =
    let
        pattern : String
        pattern =
            patternOf route

        diagnostic : String -> Diagnostic
        diagnostic problem =
            { severity = Error
            , title = "BAD ROUTE"
            , message = "The route `" ++ pattern ++ "` " ++ problem ++ ", so its pages could not be written."
            , sourcePath = Nothing
            , span = Nothing
            , hint = Just "A pattern starts with `/` and separates its segments with single slashes, as in `/posts/:slug/` or `/404.html`."
            }
    in
    patternProblem pattern
        |> Maybe.map
            (\problem ->
                case problem of
                    NoLeadingSlash ->
                        diagnostic "does not start with `/`"

                    QueryOrFragment ->
                        diagnostic "contains `?` or `#`, which would start a query or a fragment"

                    EmptySegment ->
                        diagnostic "has an empty segment"

                    DotSegment segment ->
                        diagnostic ("has a `" ++ segment ++ "` segment")
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
                        Ok (joinPath context.basePath (fillSlug document.slug pattern))

                    Nothing ->
                        Err (ToCollectionWithoutPages document.collection)


{-| Join two URL paths without doubling the slash between them.
-}
joinPath : String -> String -> String
joinPath base path =
    dropTrailingSlash base ++ "/" ++ dropLeadingSlash path


dropTrailingSlash : String -> String
dropTrailingSlash path =
    if String.endsWith "/" path then
        String.dropRight 1 path

    else
        path


dropLeadingSlash : String -> String
dropLeadingSlash path =
    if String.startsWith "/" path then
        String.dropLeft 1 path

    else
        path


fillSlug : String -> String -> String
fillSlug slug =
    String.replace ":slug" slug


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


{-| A page a route made, before its links are resolved and it is checked.

`route` is the route's place in the site's list, because two routes can have
the same pattern.

-}
type alias UncheckedPage =
    { route : Int
    , pattern : String
    , url : String
    , page : Page
    }


{-| The pages a route makes. A document whose body has problems (reported
once, by `renderSite`) gets no page, but its frontmatter is still checked.
-}
pagesOf : List ( Document, Result (List Diagnostic) (List Html) ) -> Int -> Route -> List (Result (List Diagnostic) UncheckedPage)
pagesOf bodies index route =
    case route of
        Single single ->
            [ Ok { route = index, pattern = single.pattern, url = single.pattern, page = single.page } ]

        EachItem item ->
            bodies
                |> List.filter (\( document, _ ) -> document.collection == item.collection)
                |> List.filterMap
                    (\( document, body ) ->
                        case ( item.templateFor document, body ) of
                            ( Ok template, Ok html ) ->
                                Just
                                    (Ok
                                        { route = index
                                        , pattern = item.pattern
                                        , url = fillSlug document.slug item.pattern
                                        , page = template html
                                        }
                                    )

                            ( Err problems, _ ) ->
                                Just (Err (List.map (frontmatterDiagnostic document) problems))

                            ( Ok _, Err _ ) ->
                                Nothing
                    )


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
pathOf : String -> String
pathOf url =
    let
        relative : String
        relative =
            dropLeadingSlash url
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
                    pathOf page.url
            in
            case Dict.get path seen of
                Just first ->
                    ( seen, kept, duplicate path first page :: duplicates )

                Nothing ->
                    ( Dict.insert path page seen, page :: kept, duplicates )

        ( _, written, found ) =
            List.foldl step ( Dict.empty, [], [] ) pages
    in
    -- A route without `:slug` makes the same page for every document.
    ( List.reverse written, unique (List.reverse found) )


duplicate : String -> UncheckedPage -> UncheckedPage -> Diagnostic
duplicate path first second =
    if first.route == second.route then
        { severity = Error
        , title = "DUPLICATE PAGE"
        , message = "The route `" ++ first.pattern ++ "` makes the page `" ++ path ++ "` more than once."
        , sourcePath = Nothing
        , span = Nothing
        , hint = Just "Put `:slug` in the pattern of an item route, so that each document gets its own page."
        }

    else
        { severity = Error
        , title = "DUPLICATE PAGE"
        , message = "The routes `" ++ first.pattern ++ "` and `" ++ second.pattern ++ "` both make the page `" ++ path ++ "`."
        , sourcePath = Nothing
        , span = Nothing
        , hint = Nothing
        }


{-| Resolve a page's links, check its HTML and render it.
-}
finish : Context -> String -> UncheckedPage -> Result (List Diagnostic) Protocol.Page
finish context language { pattern, url, page } =
    let
        subject : String
        subject =
            "While rendering `" ++ url ++ "` from the route `" ++ pattern ++ "`,"

        head : List Html
        head =
            [ Html.node "title" [] [ Html.text page.title ] ]

        body : List Html
        body =
            List.map (Html.resolveLinks (linkTarget context >> Result.toMaybe)) page.body

        linkProblems : List Diagnostic
        linkProblems =
            page.body
                |> List.concatMap Html.links
                |> List.filterMap
                    (\ref ->
                        linkTarget context ref
                            |> errorOf
                            |> Maybe.map
                                (linkDiagnostic
                                    { subject = subject ++ " a `Sheaf.link` points to"
                                    , sourcePath = Nothing
                                    , span = Nothing
                                    }
                                    ref
                                )
                    )

        htmlProblems : List Diagnostic
        htmlProblems =
            List.concatMap Html.problems (head ++ body)
                |> List.map (invalidHtml subject)
    in
    case linkProblems ++ htmlProblems of
        [] ->
            Ok
                { path = pathOf url
                , html = Html.document { lang = language, head = head, body = body }
                }

        problems ->
            Err problems


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
