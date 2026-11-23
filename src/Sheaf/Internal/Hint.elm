module Sheaf.Internal.Hint exposing (didYouMean, joinWith)

{-| Hints for a name that matches nothing, shared by every diagnostic that
suggests one.

@docs didYouMean, joinWith

-}


{-| A hint for a `typed` name that is none of the `known` ones: the known names
close to it, or else all of them, introduced by `listAll`, which receives them
as "`a`, `b` and `c`". There is no hint when nothing is known.
-}
didYouMean : (String -> String) -> List String -> String -> Maybe String
didYouMean listAll known typed =
    case suggestions known typed of
        [] ->
            case known of
                [] ->
                    Nothing

                _ ->
                    Just (listAll (joinWith "and" (List.map (\name -> "`" ++ name ++ "`") known)))

        [ only ] ->
            Just ("Did you mean `" ++ only ++ "`?")

        several ->
            Just ("Did you mean one of these?\n\n" ++ String.join "\n" (List.map (\name -> "    " ++ name) several))


{-| Up to three known names close to `typed`, closest first.

A name is close when it is within a third of the typed length in edits, but
never fewer than two: a transposition such as `tilte` costs two edits, and a
single edit would miss it. It is never the whole word, so short names such as
`a` do not suggest every other short name.

-}
suggestions : List String -> String -> List String
suggestions known typed =
    let
        lowered : String
        lowered =
            String.toLower typed

        allowed : Int
        allowed =
            max 2 (String.length lowered // 3)
    in
    known
        |> List.map (\name -> ( editDistance lowered (String.toLower name), name ))
        |> List.filter (\( distance, _ ) -> distance <= allowed && distance < String.length lowered)
        |> List.sortBy Tuple.first
        |> List.take 3
        |> List.map Tuple.second


{-| Levenshtein distance, one row of the edit table at a time.
-}
editDistance : String -> String -> Int
editDistance from to =
    let
        targets : List Char
        targets =
            String.toList to
    in
    String.toList from
        |> List.foldl (\char row -> nextRow char targets row) (List.range 0 (List.length targets))
        |> List.reverse
        |> List.head
        |> Maybe.withDefault 0


nextRow : Char -> List Char -> List Int -> List Int
nextRow char targets previous =
    case previous of
        [] ->
            []

        firstOfPrevious :: aboves ->
            buildRow char targets (firstOfPrevious + 1) previous aboves


{-| `diagonals` and `aboves` are the previous row, one column apart, so each
cell can look at its upper-left and upper neighbours.
-}
buildRow : Char -> List Char -> Int -> List Int -> List Int -> List Int
buildRow char targets left diagonals aboves =
    case ( targets, diagonals, aboves ) of
        ( target :: remainingTargets, diagonal :: _, above :: remainingAboves ) ->
            let
                substitution : Int
                substitution =
                    if char == target then
                        diagonal

                    else
                        diagonal + 1

                here : Int
                here =
                    min substitution (min (above + 1) (left + 1))
            in
            left :: buildRow char remainingTargets here aboves remainingAboves

        _ ->
            [ left ]


{-| "`a`, `b` or `c`": names joined with a final conjunction.
-}
joinWith : String -> List String -> String
joinWith conjunction items =
    case List.reverse items of
        [] ->
            ""

        [ only ] ->
            only

        last :: reversedInit ->
            String.join ", " (List.reverse reversedInit) ++ " " ++ conjunction ++ " " ++ last
