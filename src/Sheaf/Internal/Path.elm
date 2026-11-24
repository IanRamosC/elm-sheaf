module Sheaf.Internal.Path exposing (join, isSitePath, dropLeadingSlash, dropTrailingSlash)

{-| URL paths, shared by the renderer and the parts of a page that hold a path.

@docs join, isSitePath, dropLeadingSlash, dropTrailingSlash

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
