module Sheaf.Internal.Render exposing (render)

{-| Building a whole site from the host's request.

It takes the request as JSON, so that tests drive it exactly as the host does.

@docs render

-}

import Dict exposing (Dict)
import Json.Decode as Decode
import Sheaf.Html exposing (Html)
import Sheaf.Internal.Check as Check exposing (CheckedPage, LinkProblem(..), Location(..), UncheckedPage)
import Sheaf.Internal.Component as Component exposing (Component)
import Sheaf.Internal.Feed as Feed
import Sheaf.Internal.Frontmatter as Frontmatter
import Sheaf.Internal.Grouping as Grouping exposing (GroupPages, Grouped)
import Sheaf.Internal.Head exposing (FeedFormat(..))
import Sheaf.Internal.Hint as Hint
import Sheaf.Internal.Html as Html exposing (Url(..))
import Sheaf.Internal.Listing as Listing exposing (Body)
import Sheaf.Internal.Markdown as Markdown exposing (Problem(..))
import Sheaf.Internal.Output as Output exposing (Output(..))
import Sheaf.Internal.Path as Path
import Sheaf.Internal.Pattern as Pattern
import Sheaf.Internal.Protocol as Protocol exposing (Diagnostic, Document, GroupSlug, Request, Response, Severity(..), SitemapEntry)
import Sheaf.Internal.Redirect as Redirect exposing (Redirect)
import Sheaf.Internal.Results as Results
import Sheaf.Internal.RouteCheck as RouteCheck
import Sheaf.Internal.Site as Site exposing (Feed(..), FrontmatterProblems, Page, Route(..), Site(..))
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
    , components : Dict String Component
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
            , components = Component.byName site.components
            }

        feedCollections : List String
        feedCollections =
            List.map collectionOfFeed site.feeds

        used : List String
        used =
            Results.unique (List.filterMap Site.collectionOf site.routes ++ feedCollections)

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

        -- Found once, because each finding decodes a whole collection.
        groupings : Dict Int Grouped
        groupings =
            Grouping.groupRoutes context.slugs bodies goodRoutes

        made : List (Result (List Diagnostic) UncheckedPage)
        made =
            List.concatMap (\( index, route ) -> pagesOf context bodies groupings index route) goodRoutes

        groupPages : GroupPages
        groupPages =
            Grouping.groupPages goodRoutes groupings

        -- A feed item's broken links are not checked again: its item page
        -- has the same body, and reports them when it shows it.
        feeds : List (Result (List Diagnostic) Protocol.Feed)
        feeds =
            List.map (Feed.render context (urlTarget context groupPages) bodies) site.feeds

        written : { pages : List UncheckedPage, redirects : List Redirect, diagnostics : List Diagnostic }
        written =
            Output.withoutClashes
                (List.map PageFile (List.filterMap Result.toMaybe made)
                    ++ List.concatMap Feed.outputs site.feeds
                    ++ [ Sitemap ]
                    ++ List.map RedirectFile (List.concatMap (redirectsOf context) published)
                )

        checked : List CheckedPage
        checked =
            List.map
                (Check.check
                    { origin = context.origin
                    , basePath = context.basePath
                    , linkProblem = linkTarget context >> Results.error
                    , groupLinkProblem = Grouping.linkTarget context groupPages >> Results.error
                    , feedPaths = feedPaths site.feeds
                    }
                )
                written.pages

        good : List CheckedPage
        good =
            List.filter (\page -> List.isEmpty page.brokenLinks && List.isEmpty page.problems) checked
    in
    { site = site.metadata
    , pages =
        List.map (write (urlTarget context groupPages) site.metadata.language) good
            ++ List.map (writeRedirect context site.metadata.language) written.redirects
    , feeds = List.filterMap Result.toMaybe feeds
    , sitemap = List.filterMap (sitemapEntry context) good
    , diagnostics =
        -- A problem is found as often as it is decoded or checked: by a feed
        -- and a route that share a collection's frontmatter, by two routes
        -- over one collection, or by a third route clashing with the second.
        Results.unique
            (List.concat
                [ List.filterMap RouteCheck.badRoute site.routes
                , Component.siteProblems site.components
                , List.concatMap Results.errors feeds
                , unknownCollections used request.collections
                , Listing.missingDates (Results.unique (List.filterMap Site.datedCollection site.routes ++ feedCollections)) published
                , List.concatMap (Tuple.second >> Results.errors) bodies
                , Grouping.diagnostics goodRoutes groupings
                , List.concatMap Results.errors made
                , Check.brokenLinkDiagnostics checked
                , List.concatMap .problems checked
                , List.filterMap (aliasWithoutPage context) published
                , written.diagnostics
                ]
            )
    }


{-| The paths a head tag can link to for a format: the files the feeds write.
-}
feedPaths : List Feed -> FeedFormat -> List String
feedPaths feeds format =
    List.concatMap Feed.outputs feeds
        |> List.filterMap
            (\output ->
                case ( output, format ) of
                    ( FeedFile "RSS" path, Rss ) ->
                        Just path

                    ( FeedFile "Atom" path, Atom ) ->
                        Just path

                    _ ->
                        Nothing
            )


{-| A feed uses its collection, and lists it by date as a listing route does.
-}
collectionOfFeed : Feed -> String
collectionOfFeed (Feed feed) =
    feed.collection



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


{-| Where a URL left to the renderer points. A site path that is not valid is
reported by `Html.problems`, and its page is not written.
-}
urlTarget : Context -> GroupPages -> Url -> Maybe String
urlTarget context groupPages url =
    case url of
        DocumentUrl ref ->
            Result.toMaybe (linkTarget context ref)

        GroupUrl link ->
            Result.toMaybe (Grouping.linkTarget context groupPages link)

        SitePath path ->
            Just (Path.join context.basePath path)



-- BODIES


{-| A document's Markdown, rendered once however many routes use it.
-}
renderBody : Context -> Document -> Result (List Diagnostic) (List Html)
renderBody context document =
    Markdown.render
        { resolve = linkTarget context >> Result.toMaybe, components = context.components }
        (Markdown.fromNode document.tree)
        |> Result.mapError (List.filterMap (bodyDiagnostic context document))


bodyDiagnostic : Context -> Document -> Markdown.Problem -> Maybe Diagnostic
bodyDiagnostic context document problem =
    case problem of
        UnresolvedLink link ->
            let
                ref : Ref
                ref =
                    Ref.fromId link.id
            in
            linkTarget context ref
                |> Results.error
                |> Maybe.map
                    (Check.linkDiagnostic
                        { subject = "This document links to"
                        , sourcePath = Just document.sourcePath
                        , span = Just link.span
                        }
                        ref
                    )

        Located located ->
            Just
                { severity = Error
                , title = located.title
                , message = located.message
                , sourcePath = Just document.sourcePath
                , span = Just located.span
                , hint = located.hint
                }



-- REDIRECTS


{-| A redirect for each of a document's aliases, to its item page. Two aliases
written as the same file, such as `/old` and `/old/`, are one redirect, and
so are two that differ only in case, as output paths are compared everywhere.
-}
redirectsOf : Context -> Document -> List Redirect
redirectsOf context document =
    case Dict.get document.collection context.itemPatterns of
        Just pattern ->
            firstAtEachFile document.aliases
                |> List.map
                    (\alias ->
                        { from = alias
                        , to = Pattern.fill Pattern.Slug document.slug pattern
                        , sourcePath = document.sourcePath
                        }
                    )

        Nothing ->
            []


firstAtEachFile : List String -> List String
firstAtEachFile aliases =
    List.foldl
        (\alias ( files, kept ) ->
            let
                file : String
                file =
                    String.toLower (Redirect.fileOf alias)
            in
            if List.member file files then
                ( files, kept )

            else
                ( file :: files, alias :: kept )
        )
        ( [], [] )
        aliases
        |> Tuple.second
        |> List.reverse


aliasWithoutPage : Context -> Document -> Maybe Diagnostic
aliasWithoutPage context document =
    if List.isEmpty document.aliases || Dict.member document.collection context.itemPatterns then
        Nothing

    else
        Just
            { severity = Error
            , title = "ALIAS WITHOUT PAGE"
            , message = "This document has aliases, but the collection `" ++ document.collection ++ "` has no `eachItem` route, so there is no page for them to redirect to."
            , sourcePath = Just document.sourcePath
            , span =
                Dict.get "aliases" document.frontmatterPositions
                    |> Maybe.map (\position -> Maybe.withDefault position.value position.key)
            , hint = Just ("Add a `Route.eachItem` route for `" ++ document.collection ++ "`, or remove `aliases`.")
            }


writeRedirect : Context -> String -> Redirect -> Protocol.Page
writeRedirect context language redirect =
    { path = Redirect.fileOf redirect.from
    , html = Redirect.page { language = language, origin = context.origin, basePath = context.basePath, to = redirect.to }
    , aliasOf = Just redirect.sourcePath
    }



-- PAGES


{-| The pages a route makes. A document whose body has problems (reported
once, by `renderSite`) gets no page, but its frontmatter is still checked.
-}
pagesOf : Context -> List Body -> Dict Int Grouped -> Int -> Route -> List (Result (List Diagnostic) UncheckedPage)
pagesOf context bodies groupings index route =
    let
        madeAt : String -> Page -> UncheckedPage
        madeAt url page =
            { route = index, routeName = Site.nameOf route, location = At url, page = page, lastModified = Nothing }

        groupedPages : (Grouped -> List (Result (List FrontmatterProblems) UncheckedPage)) -> List (Result (List Diagnostic) UncheckedPage)
        groupedPages pagesFor =
            -- `renderSite` groups the documents of every grouping route it asks pages of.
            case Dict.get index groupings of
                Just grouped ->
                    Grouping.whole grouped (pagesFor grouped)

                Nothing ->
                    []
    in
    case route of
        Single single ->
            [ Ok (madeAt single.pattern single.page) ]

        NotFound page ->
            [ Ok { route = index, routeName = Site.nameOf route, location = InPlaceOfMissingPages, page = page, lastModified = Nothing } ]

        EachItem item ->
            let
                neighboursOf : Document -> Site.Neighbours
                neighboursOf =
                    Listing.neighbours item.order item.collection bodies

                -- Applied once, so the collection is decoded once for all its pages.
                templateFor : Site.Neighbours -> Result (List Frontmatter.Problem) (List Html -> Page)
                templateFor =
                    if item.listsCollection then
                        item.templateFor (List.map .document (Tuple.first (Listing.listOf item.order item.collection bodies)))

                    else
                        item.templateFor []
            in
            bodies
                |> List.filter (\( document, _ ) -> document.collection == item.collection)
                |> List.filterMap
                    (\( document, body ) ->
                        case ( templateFor (neighboursOf document), body ) of
                            ( Ok template, Ok html ) ->
                                let
                                    made : UncheckedPage
                                    made =
                                        madeAt (Pattern.fill Pattern.Slug document.slug item.pattern) (template html)

                                    -- The host sends `updated` only when the author wrote one.
                                    updated : Maybe Protocol.Date
                                    updated =
                                        case document.updated of
                                            Just _ ->
                                                document.updated

                                            Nothing ->
                                                document.date
                                in
                                Just (Ok { made | lastModified = Maybe.map .posix updated })

                            ( Err problems, _ ) ->
                                Just (Err (List.map (Listing.frontmatterDiagnostic document) problems))

                            ( Ok _, Err _ ) ->
                                Nothing
                    )

        Paginated listing ->
            let
                ( items, complete ) =
                    Listing.listOf listing.order listing.collection bodies
            in
            Listing.paginate { basePath = context.basePath, pattern = listing.pattern, perPage = listing.perPage } items
                |> List.map (\page -> Result.map (madeAt page.url) (listing.templateFor page.pagination page.items))
                |> Listing.whole complete

        AllItems listing ->
            let
                ( items, complete ) =
                    Listing.listOf listing.order listing.collection bodies
            in
            [ Result.map (madeAt listing.pattern) (listing.templateFor items) ]
                |> Listing.whole complete

        GroupedBy grouped ->
            groupedPages
                (\{ groups } ->
                    List.concatMap
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
                        groups
                )

        AllGroups all ->
            groupedPages
                (\{ groups } ->
                    [ Result.map (madeAt all.pattern) (all.templateFor (List.map (\group -> { name = group.name, items = group.items }) groups)) ]
                )


{-| An HTML page for search engines to find. The 404 page has no URL of its
own, and a file such as `humans.txt` is not a page.
-}
sitemapEntry : Context -> CheckedPage -> Maybe SitemapEntry
sitemapEntry context { unchecked } =
    case unchecked.location of
        At url ->
            if String.endsWith ".html" (Output.pathOf unchecked.location) then
                Just { url = context.origin ++ Path.join context.basePath url, lastModified = unchecked.lastModified }

            else
                Nothing

        InPlaceOfMissingPages ->
            Nothing


{-| Resolve a page's URLs and render it.
-}
write : (Url -> Maybe String) -> String -> CheckedPage -> Protocol.Page
write resolve language { unchecked, head } =
    { path = Output.pathOf unchecked.location
    , html =
        Html.document
            { lang = language
            , head = head
            , body = List.map (Html.resolveUrls resolve) unchecked.page.body
            }
    , aliasOf = Nothing
    }
