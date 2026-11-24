module Sheaf.Internal.Pattern exposing
    ( Kind(..), Problem(..), problem
    , Placeholder(..), fill, pageOf
    )

{-| Route patterns: which ones a kind of route accepts, and the URLs they give.

A placeholder such as `:slug` is a whole segment, so `/posts/:slug/` has one
and `/posts/:slugger/` has the placeholder `:slugger`, which no route fills.


# Checking

@docs Kind, Problem, problem


# Filling

@docs Placeholder, fill, pageOf

-}

import Sheaf.Internal.Path as Path


{-| What a kind of route asks of its pattern.

  - `Fixed`: one page at the pattern, as for `single` and `allItems`.
  - `Item`: a page for each document, at `:slug`.
  - `Listing`: page 1 at the pattern and page n under it, at `page/<n>/`.

-}
type Kind
    = Fixed
    | Item
    | Listing


{-| A segment that a route replaces with a value of each page.
-}
type Placeholder
    = Slug


{-| Why a pattern cannot be used by a kind of route.
-}
type Problem
    = NoLeadingSlash
    | QueryOrFragment
    | EmptySegment
    | DotSegment String
    | UnknownPlaceholder String
    | MissingPlaceholder Placeholder
    | NotAFolder


{-| The first problem of a pattern for a kind of route, if it has one.

`NoLeadingSlash`, `QueryOrFragment`, `EmptySegment` and `DotSegment` make a
pattern that cannot be turned into a file path inside the output folder, or a
URL that leads back to it, whatever the kind of route.

-}
problem : Kind -> String -> Maybe Problem
problem kind pattern =
    [ shapeProblem pattern
    , placeholderProblem kind (segments pattern)
    , folderProblem kind pattern
    ]
        |> List.filterMap identity
        |> List.head


shapeProblem : String -> Maybe Problem
shapeProblem pattern =
    if not (String.startsWith "/" pattern) then
        Just NoLeadingSlash

    else if String.contains "?" pattern || String.contains "#" pattern then
        Just QueryOrFragment

    else if List.member "" (segments pattern) then
        Just EmptySegment

    else
        segments pattern
            |> List.filter (\segment -> segment == "." || segment == "..")
            |> List.head
            |> Maybe.map DotSegment


placeholderProblem : Kind -> List String -> Maybe Problem
placeholderProblem kind patternSegments =
    let
        filled : Maybe Placeholder
        filled =
            placeholderOf kind

        unknown : Maybe String
        unknown =
            patternSegments
                |> List.filter (\segment -> String.startsWith ":" segment && Just segment /= Maybe.map name filled)
                |> List.head
    in
    case ( unknown, filled ) of
        ( Just segment, _ ) ->
            Just (UnknownPlaceholder segment)

        ( Nothing, Just needed ) ->
            if List.member (name needed) patternSegments then
                Nothing

            else
                Just (MissingPlaceholder needed)

        ( Nothing, Nothing ) ->
            Nothing


{-| Later pages of a listing are written under its first one.
-}
folderProblem : Kind -> String -> Maybe Problem
folderProblem kind pattern =
    if kind == Listing && not (String.endsWith "/" pattern) then
        Just NotAFolder

    else
        Nothing


{-| A trailing `/` makes the pattern a folder, so its empty last segment is not
one of these.
-}
segments : String -> List String
segments pattern =
    if pattern == "/" then
        []

    else
        String.split "/" (Path.dropTrailingSlash (String.dropLeft 1 pattern))


placeholderOf : Kind -> Maybe Placeholder
placeholderOf kind =
    case kind of
        Item ->
            Just Slug

        Fixed ->
            Nothing

        Listing ->
            Nothing


name : Placeholder -> String
name placeholder =
    case placeholder of
        Slug ->
            ":slug"


{-| The pattern with each `placeholder` segment replaced by `value`.

    fill Slug "hello" "/posts/:slug/" == "/posts/hello/"

-}
fill : Placeholder -> String -> String -> String
fill placeholder value pattern =
    pattern
        |> String.split "/"
        |> List.map
            (\segment ->
                if segment == name placeholder then
                    value

                else
                    segment
            )
        |> String.join "/"


{-| The URL of page `n` of a listing. The first page is the pattern itself, so
that `/` and never `/page/1/` is the home page.

    pageOf 3 "/archive/" == "/archive/page/3/"

-}
pageOf : Int -> String -> String
pageOf n pattern =
    if n == 1 then
        pattern

    else
        pattern ++ "page/" ++ String.fromInt n ++ "/"
