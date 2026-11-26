module Sheaf.Internal.Grouping exposing
    ( Grouped, groupRoutes, whole
    , diagnostics
    , GroupPages, groupPages, linkTarget
    )

{-| What grouping routes share: the groups of each route's documents, found
once per build and used to write its pages, to report its problems and to
point links at its groups.

@docs Grouped, groupRoutes, whole
@docs diagnostics
@docs GroupPages, groupPages, linkTarget

-}

import Dict exposing (Dict)
import Set exposing (Set)
import Sheaf.Internal.Check exposing (GroupLinkProblem(..))
import Sheaf.Internal.Group as Group exposing (Group)
import Sheaf.Internal.Html exposing (GroupLink)
import Sheaf.Internal.Listing as Listing exposing (Body)
import Sheaf.Internal.Path as Path
import Sheaf.Internal.Pattern as Pattern
import Sheaf.Internal.Protocol exposing (Diagnostic, GroupSlug)
import Sheaf.Internal.Site as Site exposing (FrontmatterProblems, Grouping, ListedDocument, Route)


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


{-| The groups of every grouping route, by the route's place in the site's
list of routes.
-}
groupRoutes : Dict String GroupSlug -> List Body -> List ( Int, Route ) -> Dict Int Grouped
groupRoutes slugs bodies routes =
    routes
        |> List.filterMap (\( index, route ) -> Maybe.map (\grouping -> ( index, groupDocuments slugs bodies grouping )) (Site.groupingOf route))
        |> Dict.fromList


groupDocuments : Dict String GroupSlug -> List Body -> Grouping -> Grouped
groupDocuments slugs bodies grouping =
    let
        ( items, complete ) =
            Listing.listOf grouping.order grouping.collection bodies

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
            Group.group slugs valued
    in
    { groups = groups, problems = problems, complete = complete, invalid = invalid }


{-| A grouping route is written whole or not at all, like a listing. Its
problems with values are reported by [`diagnostics`](#diagnostics), once for
all the routes that find them.
-}
whole : Grouped -> List (Result (List FrontmatterProblems) page) -> List (Result (List Diagnostic) page)
whole grouped pages =
    let
        undecoded : List (Result (List FrontmatterProblems) page)
        undecoded =
            if List.isEmpty grouped.invalid then
                []

            else
                [ Err grouped.invalid ]
    in
    Listing.whole (grouped.complete && List.isEmpty grouped.problems) (undecoded ++ pages)


{-| The problems of the values routes group by. Routes grouping the same
documents by the same values find the same problems, so each is reported once,
naming the first route that found it.
-}
diagnostics : List ( Int, Route ) -> Dict Int Grouped -> List Diagnostic
diagnostics routes grouped =
    routes
        |> List.concatMap
            (\( index, route ) ->
                Dict.get index grouped
                    |> Maybe.map (.problems >> List.map (Tuple.pair (Site.nameOf route)))
                    |> Maybe.withDefault []
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



-- LINKS


{-| The slugs of the groups each `groupedBy` pattern has pages for.
-}
type alias GroupPages =
    Dict String (Set String)


{-| The group pages links can point to, from the first `groupedBy` route with
each pattern.
-}
groupPages : List ( Int, Route ) -> Dict Int Grouped -> GroupPages
groupPages routes grouped =
    routes
        |> List.filterMap
            (\( index, route ) ->
                Maybe.map2 (\pattern { groups } -> ( pattern, Set.fromList (List.map .slug groups) ))
                    (Site.groupedPattern route)
                    (Dict.get index grouped)
            )
        -- Reversed, because `Dict.fromList` keeps the last.
        |> List.reverse
        |> Dict.fromList


{-| Where a link to a group points, with the base path.
-}
linkTarget : { a | basePath : String, slugs : Dict String GroupSlug } -> GroupPages -> GroupLink -> Result GroupLinkProblem String
linkTarget { basePath, slugs } pages link =
    case ( Dict.get link.pattern pages, Dict.get link.value slugs ) of
        ( Nothing, _ ) ->
            Err (NoGroupedRoute (Dict.keys pages))

        ( Just _, Nothing ) ->
            Err ValueWithoutSlug

        ( Just groupSlugs, Just { slug } ) ->
            if Set.member slug groupSlugs then
                Ok (Path.join basePath (Pattern.fill Pattern.Group slug link.pattern))

            else
                Err EmptyGroup
