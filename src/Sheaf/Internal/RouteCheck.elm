module Sheaf.Internal.RouteCheck exposing (badRoute, badFeedFile, badGroupedFeedFile, badFeedLimit)

{-| The rules a route must follow before it makes any page: a pattern its kind
of route accepts, and at least one document on each page. A feed's files
follow the same rules for their paths, and a feed keeps at least one item.

@docs badRoute, badFeedFile, badGroupedFeedFile, badFeedLimit

-}

import Sheaf.Internal.Pattern as Pattern
import Sheaf.Internal.Protocol exposing (Diagnostic, Severity(..))
import Sheaf.Internal.Site as Site exposing (Route)


{-| What breaks a rule: a route, the file of a feed in one of its formats,
such as `RSS`, the file of a feed for each group in a format, or a whole feed,
named by its RSS file.
-}
type Subject
    = RouteSubject Route
    | FeedFile String String
    | GroupedFeedFile String String
    | FeedSubject String


type RouteProblem
    = BadPattern Pattern.Problem
    | Reserved
    | TooFewPerPage Int
    | TooLowLimit Int


routeProblem : Route -> Maybe RouteProblem
routeProblem route =
    case Site.patternOf route of
        Just ( kind, pattern ) ->
            case Pattern.problem kind pattern of
                Just problem ->
                    Just (BadPattern problem)

                Nothing ->
                    if isReserved pattern then
                        Just Reserved

                    else
                        perPageProblem route

        Nothing ->
            perPageProblem route


perPageProblem : Route -> Maybe RouteProblem
perPageProblem route =
    Site.perPageOf route
        |> Maybe.andThen
            (\perPage ->
                -- Cutting a list into pieces of none never ends, and the
                -- host cannot stop the worker while it runs.
                if perPage < 1 then
                    Just (TooFewPerPage perPage)

                else
                    Nothing
            )


{-| Sheaf writes its own files, such as images, under `/_sheaf/`. Case is
ignored, because on a file system that ignores it `/_Sheaf/` is that folder.
-}
isReserved : String -> Bool
isReserved pattern =
    let
        lower : String
        lower =
            String.toLower pattern
    in
    lower == "/_sheaf" || String.startsWith "/_sheaf/" lower


{-| Why a route makes no pages, if it breaks a rule.
-}
badRoute : Route -> Maybe Diagnostic
badRoute route =
    Maybe.map (diagnostic (RouteSubject route)) (routeProblem route)


{-| Why a feed's file in `format` cannot be written at `path`, if it cannot.

    badFeedFile "RSS" "/feed.xml" == Nothing

-}
badFeedFile : String -> String -> Maybe Diagnostic
badFeedFile format path =
    Pattern.problem Pattern.File path
        |> Maybe.map (BadPattern >> diagnostic (FeedFile format path))


{-| Why the files of a feed for each group in `format` cannot be written at
`path`, which needs `:group` once, if they cannot.

    badGroupedFeedFile "RSS" "/tags/:group/feed.xml" == Nothing

-}
badGroupedFeedFile : String -> String -> Maybe Diagnostic
badGroupedFeedFile format path =
    Pattern.problem Pattern.GroupedFile path
        |> Maybe.map (BadPattern >> diagnostic (GroupedFeedFile format path))


{-| Why a feed, named by its RSS file `rss`, cannot keep `limit` items, if it
cannot.

    badFeedLimit "/feed.xml" (Just 20) == Nothing

-}
badFeedLimit : String -> Maybe Int -> Maybe Diagnostic
badFeedLimit rss limit =
    case limit of
        Just count ->
            if count < 1 then
                Just (diagnostic (FeedSubject rss) (TooLowLimit count))

            else
                Nothing

        Nothing ->
            Nothing


diagnostic : Subject -> RouteProblem -> Diagnostic
diagnostic subject problem =
    let
        ( name, result ) =
            case subject of
                RouteSubject route ->
                    ( "The route `" ++ Site.nameOf route ++ "`", "its pages" )

                FeedFile format path ->
                    ( "The " ++ format ++ " feed `" ++ path ++ "`", "it" )

                GroupedFeedFile format path ->
                    ( "The " ++ format ++ " feed `" ++ path ++ "`", "it" )

                FeedSubject rss ->
                    ( "The feed `" ++ rss ++ "`", "it" )

        breaks : String -> Maybe String -> Diagnostic
        breaks rule hint =
            { severity = Error
            , title = "BAD ROUTE"
            , message = name ++ " " ++ rule ++ ", so " ++ result ++ " could not be written."
            , sourcePath = Nothing
            , span = Nothing
            , hint = hint
            }

        shapeHint : Maybe String
        shapeHint =
            Just "A pattern starts with `/` and separates its segments with single slashes, as in `/posts/:slug/` or `/humans.txt`."

        fileHint : Maybe String
        fileHint =
            case subject of
                GroupedFeedFile _ _ ->
                    Just "Name the file, as in `/tags/:group/feed.xml`."

                _ ->
                    Just "Name the file, as in `/feed.xml` or `/atom.xml`."

        groupFileHint : Maybe String
        groupFileHint =
            Just "Put `:group` in a segment of its own, as in `/tags/:group/feed.xml`."
    in
    case problem of
        BadPattern Pattern.NoLeadingSlash ->
            breaks "does not start with `/`" shapeHint

        BadPattern Pattern.QueryOrFragment ->
            breaks "contains `?` or `#`, which would start a query or a fragment" shapeHint

        BadPattern Pattern.EmptySegment ->
            breaks "has an empty segment" shapeHint

        BadPattern (Pattern.DotSegment segment) ->
            breaks ("has a `" ++ segment ++ "` segment") shapeHint

        BadPattern (Pattern.UnknownPlaceholder placeholder) ->
            case subject of
                RouteSubject _ ->
                    breaks ("has the placeholder `" ++ placeholder ++ "`, which this kind of route does not fill")
                        (Just "`Route.eachItem` fills `:slug` and `Route.groupedBy` fills `:group`, each in a segment of its own, as in `/posts/:slug/` or `/tags/:group/`.")

                GroupedFeedFile _ _ ->
                    breaks ("has the placeholder `" ++ placeholder ++ "`, which a feed for each group does not fill")
                        (Just "`Feed.groupedBy` fills `:group`, in a segment of its own, as in `/tags/:group/feed.xml`.")

                _ ->
                    breaks ("has the placeholder `" ++ placeholder ++ "`, but a feed is one file") fileHint

        BadPattern (Pattern.MissingPlaceholder Pattern.Slug) ->
            breaks "does not have the placeholder `:slug`, which gives each document its own page"
                (Just "Put `:slug` in a segment of its own, as in `/posts/:slug/`.")

        BadPattern (Pattern.MissingPlaceholder Pattern.Group) ->
            case subject of
                GroupedFeedFile _ _ ->
                    breaks "does not have the placeholder `:group`, which gives each group its own feed" groupFileHint

                _ ->
                    breaks "does not have the placeholder `:group`, which gives each group its own page"
                        (Just "Put `:group` in a segment of its own, as in `/tags/:group/`.")

        BadPattern (Pattern.RepeatedPlaceholder placeholder) ->
            breaks ("has the placeholder `" ++ Pattern.name placeholder ++ "` more than once, but each group's feed is one file") groupFileHint

        BadPattern Pattern.NotAFolder ->
            breaks "does not end with `/`, but its later pages are written under it"
                (Just "End the pattern with `/`, as in `/archive/`. Its second page is then `/archive/page/2/`.")

        BadPattern Pattern.NotAFile ->
            breaks "ends with `/`, but a feed is a file" fileHint

        Reserved ->
            breaks "is in `/_sheaf/`, which is reserved for files Sheaf writes"
                (Just "Choose a pattern that does not start with `/_sheaf/`.")

        TooFewPerPage perPage ->
            breaks ("has `perPage = " ++ String.fromInt perPage ++ "`, but `perPage` must be at least 1") Nothing

        TooLowLimit limit ->
            breaks ("has `limit = " ++ String.fromInt limit ++ "`, but `limit` must be at least 1") Nothing
