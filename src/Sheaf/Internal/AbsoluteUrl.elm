module Sheaf.Internal.AbsoluteUrl exposing (Base, resolve)

{-| Making a URL written in a page absolute, as a browser does against the
page's own URL, for content shown away from the site, such as in a feed.

It follows `new URL(value, base)` for the URLs a page can hold: what it does
not need, such as a base with a query, it leaves out.

@docs Base, resolve

-}

import Sheaf.Internal.Path as Path


{-| The page a URL is written in: its origin, with no trailing slash, and its
path, which starts with `/`.
-}
type alias Base =
    { origin : String
    , path : String
    }


{-| The absolute URL that `reference` points to from `base`.

    resolve { origin = "https://example.com", path = "/blog/posts/a/" } "../b/"
        == "https://example.com/blog/posts/b/"

-}
resolve : Base -> String -> String
resolve base reference =
    if hasScheme reference then
        reference

    else if String.startsWith "//" reference then
        schemeOf base.origin ++ ":" ++ reference

    else if String.startsWith "/" reference then
        base.origin ++ withoutDotSegments reference

    else if String.startsWith "#" reference || String.startsWith "?" reference || reference == "" then
        base.origin ++ base.path ++ reference

    else
        base.origin ++ withoutDotSegments (folderOf base.path ++ reference)


{-| Whether the URL starts with a scheme, such as `https:` or `mailto:`.
-}
hasScheme : String -> Bool
hasScheme url =
    case String.split ":" url of
        scheme :: _ :: _ ->
            case String.uncons scheme of
                Just ( first, rest ) ->
                    Char.isAlpha first && String.all (\c -> Char.isAlphaNum c || c == '+' || c == '.' || c == '-') rest

                Nothing ->
                    False

        _ ->
            False


schemeOf : String -> String
schemeOf origin =
    List.head (String.split ":" origin)
        |> Maybe.withDefault "https"


{-| Everything up to the last `/`, which a relative path is joined to.
-}
folderOf : String -> String
folderOf path =
    case List.reverse (String.indexes "/" path) of
        last :: _ ->
            String.left (last + 1) path

        [] ->
            "/"


{-| The URL with its `.` and `..` segments applied, as in RFC 3986 §5.2.4.
A `..` at the root stays at the root. The query and fragment are left as they
are, because they may contain anything.
-}
withoutDotSegments : String -> String
withoutDotSegments url =
    let
        pathEnd : Int
        pathEnd =
            List.minimum (String.indexes "?" url ++ String.indexes "#" url)
                |> Maybe.withDefault (String.length url)

        segments : List String
        segments =
            String.split "/" (Path.dropLeadingSlash (String.left pathEnd url))

        keep : String -> List String -> List String
        keep segment kept =
            case segment of
                "." ->
                    kept

                ".." ->
                    List.drop 1 kept

                _ ->
                    segment :: kept

        -- A path ending in `.` or `..` names a folder, so it keeps its slash.
        trailing : List String
        trailing =
            case List.head (List.reverse segments) of
                Just "." ->
                    [ "" ]

                Just ".." ->
                    [ "" ]

                _ ->
                    []
    in
    "/" ++ String.join "/" (List.reverse (List.foldl keep [] segments) ++ trailing) ++ String.dropLeft pathEnd url
