module Sheaf.Internal.Path exposing (join, isSitePath, dropLeadingSlash, dropTrailingSlash, encodeSegments)

{-| URL paths, shared by the renderer and the parts of a page that hold a path.

@docs join, isSitePath, dropLeadingSlash, dropTrailingSlash, encodeSegments

-}


{-| Join two URL paths without doubling the slash between them.

    join "/blog/" "/posts/a/" == "/blog/posts/a/"

-}
join : String -> String -> String
join base path =
    dropTrailingSlash base ++ "/" ++ dropLeadingSlash path


{-| Whether a path is written from the root of the site, so that it can get
the base path in front. A browser reads `//` as the start of another host.
-}
isSitePath : String -> Bool
isSitePath path =
    String.startsWith "/" path && not (String.startsWith "//" path)


{-| The path without a `/` at its start, if it has one.
-}
dropLeadingSlash : String -> String
dropLeadingSlash path =
    if String.startsWith "/" path then
        String.dropLeft 1 path

    else
        path


{-| The path without a `/` at its end, if it has one.
-}
dropTrailingSlash : String -> String
dropTrailingSlash path =
    if String.endsWith "/" path then
        String.dropRight 1 path

    else
        path


{-| A path written as a URL: each character a URL cannot hold as it is, such
as a space, becomes `%` and its code in hexadecimal. Characters outside ASCII
are kept, which HTML allows in a link.

    encodeSegments "my theme/a.css" == "my%20theme/a.css"

-}
encodeSegments : String -> String
encodeSegments path =
    path
        |> String.split "/"
        |> List.map (String.concat << List.map encodeChar << String.toList)
        |> String.join "/"


encodeChar : Char -> String
encodeChar char =
    let
        code : Int
        code =
            Char.toCode char
    in
    if code <= 0x20 || code == 0x7F || String.contains (String.fromChar char) "\"#%<>?[\\]^`{|}" then
        "%" ++ hexDigit (code // 16) ++ hexDigit (modBy 16 code)

    else
        String.fromChar char


hexDigit : Int -> String
hexDigit digit =
    String.slice digit (digit + 1) "0123456789ABCDEF"
