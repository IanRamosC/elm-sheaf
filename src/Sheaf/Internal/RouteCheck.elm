module Sheaf.Internal.RouteCheck exposing (badRoute)

{-| The rules a route must follow before it makes any page: a pattern its kind
of route accepts, and at least one document on each page.

@docs badRoute

-}

import Sheaf.Internal.Pattern as Pattern
import Sheaf.Internal.Protocol exposing (Diagnostic, Severity(..))
import Sheaf.Internal.Site as Site exposing (Route)


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
    let
        diagnostic : String -> Maybe String -> Diagnostic
        diagnostic problem hint =
            { severity = Error
            , title = "BAD ROUTE"
            , message = "The route `" ++ Site.nameOf route ++ "` " ++ problem ++ ", so its pages could not be written."
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
                            (Just "`Route.eachItem` fills `:slug` and `Route.groupedBy` fills `:group`, each in a segment of its own, as in `/posts/:slug/` or `/tags/:group/`.")

                    BadPattern (Pattern.MissingPlaceholder Pattern.Slug) ->
                        diagnostic "does not have the placeholder `:slug`, which gives each document its own page"
                            (Just "Put `:slug` in a segment of its own, as in `/posts/:slug/`.")

                    BadPattern (Pattern.MissingPlaceholder Pattern.Group) ->
                        diagnostic "does not have the placeholder `:group`, which gives each group its own page"
                            (Just "Put `:group` in a segment of its own, as in `/tags/:group/`.")

                    BadPattern Pattern.NotAFolder ->
                        diagnostic "does not end with `/`, but its later pages are written under it"
                            (Just "End the pattern with `/`, as in `/archive/`. Its second page is then `/archive/page/2/`.")

                    TooFewPerPage perPage ->
                        diagnostic ("has `perPage = " ++ String.fromInt perPage ++ "`, but `perPage` must be at least 1") Nothing
            )
