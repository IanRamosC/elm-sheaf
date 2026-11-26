module Sheaf.Internal.Compare exposing (byCodePoint, both)

{-| Orders that do not change from one build to the next.

@docs byCodePoint, both

-}


{-| JavaScript compares strings by UTF-16 code unit, which puts some
characters outside the Basic Multilingual Plane before others inside it.
-}
byCodePoint : String -> String -> Order
byCodePoint a b =
    compare (List.map Char.toCode (String.toList a)) (List.map Char.toCode (String.toList b))


{-| The first order, and the second where the first is a tie.
-}
both : Order -> Order -> Order
both first second =
    case first of
        EQ ->
            second

        _ ->
            first
