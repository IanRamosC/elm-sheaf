module Sheaf.Internal.Feed exposing (Context, render, outputs)

{-| The items of a feed, which the host writes as RSS and Atom.

@docs Context, render, outputs

-}

import Dict exposing (Dict)
import Sheaf.Internal.AbsoluteUrl as AbsoluteUrl
import Sheaf.Internal.Frontmatter exposing (Problem)
import Sheaf.Internal.Html as Html
import Sheaf.Internal.Listing as Listing exposing (Body)
import Sheaf.Internal.Output exposing (Output(..))
import Sheaf.Internal.Path as Path
import Sheaf.Internal.Pattern as Pattern
import Sheaf.Internal.Protocol as Protocol exposing (Diagnostic, Severity(..))
import Sheaf.Internal.RouteCheck as RouteCheck
import Sheaf.Internal.Site exposing (Description, Feed(..), ListedDocument)


{-| What a feed needs of the site: where it is served, and the pattern of the
first item route of each collection, where its items link to.
-}
type alias Context a =
    { a
        | origin : String
        , basePath : String
        , itemPatterns : Dict String String
    }


{-| A feed with its items, newest first.

A feed with a problem is not written. Its bad files and a collection with no
item route are reported here. A document that keeps it from being complete,
such as one without a date, is reported on its own, and so is a frontmatter
problem, by the item route.

-}
render : Context a -> List Body -> Feed -> Result (List Diagnostic) Protocol.Feed
render context bodies (Feed feed) =
    case List.filterMap identity [ RouteCheck.badFeedFile "RSS" feed.rss, RouteCheck.badFeedFile "Atom" feed.atom ] of
        [] ->
            case Dict.get feed.collection context.itemPatterns of
                Just pattern ->
                    let
                        ( listed, complete ) =
                            Listing.listOf feed.collection bodies
                    in
                    case ( complete, allOf (List.map (itemOf context pattern feed.describe) listed) ) of
                        ( True, Just items ) ->
                            Ok { rss = Path.dropLeadingSlash feed.rss, atom = Path.dropLeadingSlash feed.atom, items = items }

                        _ ->
                            Err []

                Nothing ->
                    Err [ noPageForFeed feed ]

        badFiles ->
            Err badFiles


{-| The files a feed writes, if their paths are good: a bad one is reported
by [`render`](#render) and never written.
-}
outputs : Feed -> List Output
outputs (Feed feed) =
    [ ( "RSS", feed.rss ), ( "Atom", feed.atom ) ]
        |> List.filter (\( format, path ) -> RouteCheck.badFeedFile format path == Nothing)
        |> List.map (\( format, path ) -> FeedFile format path)


itemOf : Context a -> String -> (Protocol.Document -> Result (List Problem) Description) -> ListedDocument -> Maybe Protocol.FeedItem
itemOf context pattern describe { document, body } =
    Maybe.map2
        (\date description ->
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
            , html = String.concat (List.map (Html.rewriteUrls absolute >> Html.toString) body)
            , date = date.posix
            , updated = (Maybe.withDefault date document.updated).posix
            }
        )
        document.date
        (Result.toMaybe (describe document))


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
