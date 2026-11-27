module Sheaf.Internal.Feed exposing (Context, Prepared, prepare, render, outputs, patterns)

{-| The items of a feed, which the host writes as RSS and Atom.

@docs Context, Prepared, prepare, render, outputs, patterns

-}

import Dict exposing (Dict)
import Sheaf.Internal.AbsoluteUrl as AbsoluteUrl
import Sheaf.Internal.Frontmatter exposing (Problem)
import Sheaf.Internal.Grouping as Grouping exposing (Grouped)
import Sheaf.Internal.Html as Html exposing (Url)
import Sheaf.Internal.Listing as Listing exposing (Body)
import Sheaf.Internal.Output exposing (Output(..))
import Sheaf.Internal.Path as Path
import Sheaf.Internal.Pattern as Pattern
import Sheaf.Internal.Protocol as Protocol exposing (Diagnostic, GroupSlug, Severity(..))
import Sheaf.Internal.Results as Results
import Sheaf.Internal.RouteCheck as RouteCheck
import Sheaf.Internal.Site exposing (Description, Feed(..), ListedDocument, SortOrder(..))


{-| What a feed needs of the site: where it is served, its title, and the
pattern of the first item route of each collection, where its items link to.
-}
type alias Context a =
    { a
        | origin : String
        , basePath : String
        , title : String
        , itemPatterns : Dict String String
    }


{-| A feed, and the groups of its documents if it is a feed for each group
and its files can be written. They are found once per build, because finding
them decodes a whole collection.
-}
type alias Prepared =
    { feed : Feed
    , grouped : Maybe Grouped
    }


{-| Group a feed's documents, if it has a feed for each group.
-}
prepare : Dict String GroupSlug -> List Body -> Feed -> Prepared
prepare slugs bodies ((Feed { grouping }) as feed) =
    { feed = feed
    , grouped =
        if List.isEmpty (problems feed) then
            Maybe.map (Grouping.groupDocuments slugs bodies) grouping

        else
            Nothing
    }


{-| A feed with its newest items, newest first, as many as its limit keeps,
or one such feed for each group. `resolve` gives the URLs its items' bodies
left to the renderer, as it does for pages: a component's links to documents
and groups, and site paths.

A feed with a problem is not written. Its bad files and limit, a collection
with no item route and the frontmatter problems of its documents, even those
past its limit, are reported here. A document that keeps it from being
complete, such as one without a date, is reported on its own, and so is a
value its groups cannot be made from.

-}
render : Context a -> (Url -> Maybe String) -> List Body -> Prepared -> Result (List Diagnostic) (List Protocol.Feed)
render context resolve bodies { feed, grouped } =
    case problems feed of
        [] ->
            itemsOf context resolve bodies feed
                |> Result.andThen (feedsOf context.title feed grouped)

        badFeed ->
            Err badFeed


{-| Every item of a feed's collection, newest first, if it can be complete.
-}
itemsOf : Context a -> (Url -> Maybe String) -> List Body -> Feed -> Result (List Diagnostic) (List Protocol.FeedItem)
itemsOf context resolve bodies (Feed feed) =
    case Dict.get feed.collection context.itemPatterns of
        Just pattern ->
            let
                ( listed, complete ) =
                    Listing.listOf ByDate feed.collection bodies
            in
            case Results.combine (List.map (itemOf context resolve pattern feed.describe) listed) of
                Ok dated ->
                    case ( complete, allOf dated ) of
                        ( True, Just items ) ->
                            Ok items

                        _ ->
                            Err []

                Err itemProblems ->
                    Err itemProblems

        Nothing ->
            Err [ noPageForFeed feed ]


{-| The feeds of a feed's items, newest first: one, or one for each group.
A document whose frontmatter does not decode has no item, so a group is
complete when the feed's items are.
-}
feedsOf : String -> Feed -> Maybe Grouped -> List Protocol.FeedItem -> Result (List Diagnostic) (List Protocol.Feed)
feedsOf siteTitle (Feed feed) grouped items =
    let
        written : String -> String -> String -> List Protocol.FeedItem -> Protocol.Feed
        written rss atom title feedItems =
            { rss = Path.dropLeadingSlash rss
            , atom = Path.dropLeadingSlash atom
            , title = title
            , items = Maybe.withDefault feedItems (Maybe.map (\limit -> List.take limit feedItems) feed.limit)
            }
    in
    case grouped of
        Nothing ->
            Ok [ written feed.rss feed.atom siteTitle items ]

        Just found ->
            if List.isEmpty found.problems then
                let
                    byDocument : Dict String Protocol.FeedItem
                    byDocument =
                        Dict.fromList (List.map (\item -> ( item.documentId, item )) items)
                in
                found.groups
                    |> List.map
                        (\group ->
                            written
                                (Pattern.fill Pattern.Group group.slug feed.rss)
                                (Pattern.fill Pattern.Group group.slug feed.atom)
                                (siteTitle ++ " · " ++ group.name)
                                (List.filterMap (\listed -> Dict.get listed.document.id byDocument) group.items)
                        )
                    |> Ok

            else
                -- Reported once for every route and feed that finds them.
                Err []


{-| The files a feed writes, if their paths are good: a bad one is reported
by [`render`](#render) and never written. A feed for each group writes a
file in each format for each group.
-}
outputs : Prepared -> List Output
outputs { feed, grouped } =
    let
        (Feed declared) =
            feed
    in
    case ( declared.grouping, grouped ) of
        ( Nothing, _ ) ->
            patterns feed

        ( Just _, Just { groups } ) ->
            goodFiles declared
                |> List.concatMap
                    (\( format, path ) ->
                        List.map (\group -> FeedFile format (Pattern.fill Pattern.Group group.slug path)) groups
                    )

        ( Just _, Nothing ) ->
            []


{-| A feed's files as written, if their paths are good, with `:group` in
those of a feed for each group.
-}
patterns : Feed -> List Output
patterns (Feed feed) =
    List.map (\( format, path ) -> FeedFile format path) (goodFiles feed)


goodFiles : { a | rss : String, atom : String, grouping : Maybe grouping } -> List ( String, String )
goodFiles feed =
    List.filter (\( format, path ) -> badFile feed format path == Nothing) [ ( "RSS", feed.rss ), ( "Atom", feed.atom ) ]


badFile : { a | grouping : Maybe grouping } -> String -> String -> Maybe Diagnostic
badFile feed =
    case feed.grouping of
        Just _ ->
            RouteCheck.badGroupedFeedFile

        Nothing ->
            RouteCheck.badFeedFile


problems : Feed -> List Diagnostic
problems (Feed feed) =
    List.filterMap identity
        [ badFile feed "RSS" feed.rss
        , badFile feed "Atom" feed.atom
        , RouteCheck.badFeedLimit feed.rss feed.limit
        ]


{-| A document's item, or nothing if it has no date, which is reported on its
own. A feed may describe a collection with other frontmatter than its item
route does, so it reports its own frontmatter problems. Its body has no
heading links, which feed readers would show as stray `#`s.
-}
itemOf : Context a -> (Url -> Maybe String) -> String -> (Protocol.Document -> Result (List Problem) Description) -> ListedDocument -> Result (List Diagnostic) (Maybe Protocol.FeedItem)
itemOf context resolve pattern describe { document, body } =
    describe document
        |> Result.mapError (List.map (Listing.frontmatterDiagnostic document))
        |> Result.map
            (\description ->
                Maybe.map
                    (\date ->
                        let
                            path : String
                            path =
                                Path.join context.basePath (Pattern.fill Pattern.Slug document.slug pattern)

                            absolute : String -> String
                            absolute =
                                AbsoluteUrl.resolve { origin = context.origin, path = path }
                        in
                        { documentId = document.id
                        , url = context.origin ++ path
                        , title = description.title
                        , summary = description.summary
                        , html = String.concat (List.map (Html.withoutHeadingLinks >> Html.resolveUrls resolve >> Html.rewriteUrls absolute >> Html.toString) body)
                        , date = date.posix
                        , updated = (Maybe.withDefault date document.updated).posix
                        }
                    )
                    document.date
            )


allOf : List (Maybe a) -> Maybe (List a)
allOf =
    List.foldr (Maybe.map2 (::)) (Just [])


noPageForFeed : { a | rss : String, collection : String } -> Diagnostic
noPageForFeed feed =
    { severity = Error
    , title = "NO PAGE FOR FEED"
    , message = "The feed `" ++ feed.rss ++ "` lists `" ++ feed.collection ++ "`, but no route gives the documents of `" ++ feed.collection ++ "` a page for its items to link to."
    , sourcePath = Nothing
    , span = Nothing
    , hint = Just ("Add a `Route.eachItem` route for the `" ++ feed.collection ++ "` collection.")
    }
