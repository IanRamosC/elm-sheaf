module Sheaf.Internal.RouteCheck exposing (badRoute, badFeedFile)

{-| The rules a route must follow before it makes any page: a pattern its kind
of route accepts, and at least one document on each page. A feed's files
follow the same rules for their paths.

@docs badRoute, badFeedFile

-}

import Sheaf.Internal.Pattern as Pattern
import Sheaf.Internal.Protocol exposing (Diagnostic, Severity(..))
import Sheaf.Internal.Site as Site exposing (Route)


{-| What breaks a rule: a route, or the file of a feed in one of its formats,
such as `RSS`.
-}
type Subject
    = RouteSubject Route
    | FeedFile String String


type RouteProblem
    = BadPattern Pattern.Problem
    | TooFewPerPage Int


routeProblem : Route -> Maybe RouteProblem
routeProblem route =
    case Maybe.andThen (\( kind, pattern ) -> Pattern.problem kind pattern) (Site.patternOf route) of
        Just problem ->
            Just (BadPattern problem)

        Nothing ->
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


diagnostic : Subject -> RouteProblem -> Diagnostic
diagnostic subject problem =
    let
        ( name, result ) =
            case subject of
                RouteSubject route ->
                    ( "The route `" ++ Site.nameOf route ++ "`", "its pages" )

                FeedFile format path ->
                    ( "The " ++ format ++ " feed `" ++ path ++ "`", "it" )

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
            Just "Name the file, as in `/feed.xml` or `/atom.xml`."
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

                FeedFile _ _ ->
                    breaks ("has the placeholder `" ++ placeholder ++ "`, but a feed is one file") fileHint

        BadPattern (Pattern.MissingPlaceholder Pattern.Slug) ->
            breaks "does not have the placeholder `:slug`, which gives each document its own page"
                (Just "Put `:slug` in a segment of its own, as in `/posts/:slug/`.")

        BadPattern (Pattern.MissingPlaceholder Pattern.Group) ->
            breaks "does not have the placeholder `:group`, which gives each group its own page"
                (Just "Put `:group` in a segment of its own, as in `/tags/:group/`.")

        BadPattern Pattern.NotAFolder ->
            breaks "does not end with `/`, but its later pages are written under it"
                (Just "End the pattern with `/`, as in `/archive/`. Its second page is then `/archive/page/2/`.")

        BadPattern Pattern.NotAFile ->
            breaks "ends with `/`, but a feed is a file" fileHint

        TooFewPerPage perPage ->
            breaks ("has `perPage = " ++ String.fromInt perPage ++ "`, but `perPage` must be at least 1") Nothing
