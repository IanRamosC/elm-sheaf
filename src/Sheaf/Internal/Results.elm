module Sheaf.Internal.Results exposing (combine, errors, error, unique)

{-| Gathering the problems of many results, so that one build reports all of
them, and reporting each once.

    combine [ Ok 1, Err [ "a" ], Err [ "b" ] ] == Err [ "a", "b" ]

@docs combine, errors, error, unique

-}


{-| Every value, or the problems of all that failed.

    combine [ Ok 1, Ok 2 ] == Ok [ 1, 2 ]

-}
combine : List (Result (List e) a) -> Result (List e) (List a)
combine results =
    case List.concatMap errors results of
        [] ->
            Ok (List.filterMap Result.toMaybe results)

        problems ->
            Err problems


{-| The problems of a result, or none.

    errors (Err [ "a", "b" ]) == [ "a", "b" ]

-}
errors : Result (List e) a -> List e
errors result =
    case result of
        Ok _ ->
            []

        Err problems ->
            problems


{-| The problem of a result, if it failed.

    error (Err "a") == Just "a"

-}
error : Result e a -> Maybe e
error result =
    case result of
        Ok _ ->
            Nothing

        Err problem ->
            Just problem


{-| The first of each item, in order.

    unique [ "b", "a", "b" ] == [ "b", "a" ]

-}
unique : List a -> List a
unique items =
    List.foldl
        (\item kept ->
            if List.member item kept then
                kept

            else
                item :: kept
        )
        []
        items
        |> List.reverse
