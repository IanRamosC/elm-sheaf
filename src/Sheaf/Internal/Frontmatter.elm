module Sheaf.Internal.Frontmatter exposing
    ( Frontmatter, Field, Positions, Problem
    , succeed, required, optional, withDefault
    , string, int, float, bool, list, oneOf, map, validate, fromDecoder
    , decode
    )

{-| Frontmatter decoders and the located problems they report.

This is the implementation of `Sheaf.Frontmatter`, plus `decode`, which only
the host-facing `Sheaf.Program` uses.

@docs Frontmatter, Field, Positions, Problem
@docs succeed, required, optional, withDefault
@docs string, int, float, bool, list, oneOf, map, validate, fromDecoder
@docs decode

-}

import Dict exposing (Dict)
import Json.Decode as Decode exposing (Decoder, Value)
import Sheaf.Internal.Protocol exposing (FieldPosition, Span)



-- TYPES


{-| A record decoder that knows the names of its fields.
-}
type Frontmatter a
    = Frontmatter
        { names : List String
        , read : Dict String Value -> Result (List FieldFailure) a
        }


{-| How to decode one value.

`singular` and `plural` name what the field accepts ("a string", "strings"),
so a list can say "a list of strings".

-}
type Field a
    = Field
        { singular : String
        , plural : String
        , read : Value -> Result (List Failure) a
        }


type FieldFailure
    = Missing String
    | Invalid String Failure


{-| Why a value was refused, and which list item (if any) it was found in.
-}
type Failure
    = WrongType { expected : String, found : String, itemPath : List Int }
    | Rejected { message : String, itemPath : List Int }


{-| Where each frontmatter value sits, by dotted path (`tags`, `tags.1`).
-}
type alias Positions =
    Dict String FieldPosition


{-| Something wrong with a document's frontmatter, ready to become a diagnostic.
-}
type alias Problem =
    { title : String
    , message : String
    , span : Maybe Span
    , hint : Maybe String
    }



-- BUILDING


{-| A decoder for a record with no fields yet.
-}
succeed : a -> Frontmatter a
succeed value =
    Frontmatter { names = [], read = \_ -> Ok value }


{-| A field that must be present.
-}
required : String -> Field a -> Frontmatter (a -> b) -> Frontmatter b
required name field =
    addField name <|
        \maybeValue ->
            case maybeValue of
                Nothing ->
                    Err [ Missing name ]

                Just value ->
                    readField name field value


{-| A field that may be absent or empty.
-}
optional : String -> Field a -> Frontmatter (Maybe a -> b) -> Frontmatter b
optional name field =
    addField name (readOptional name field)


{-| A field that may be absent or empty, replaced by a default.
-}
withDefault : String -> a -> Field a -> Frontmatter (a -> b) -> Frontmatter b
withDefault name default field =
    addField name (readOptional name field >> Result.map (Maybe.withDefault default))


addField : String -> (Maybe Value -> Result (List FieldFailure) a) -> Frontmatter (a -> b) -> Frontmatter b
addField name readValue (Frontmatter previous) =
    Frontmatter
        { names = addName name previous.names
        , read =
            \values ->
                andMap (readValue (Dict.get name values)) (previous.read values)
        }


addName : String -> List String -> List String
addName name names =
    if List.member name names then
        names

    else
        names ++ [ name ]


readOptional : String -> Field a -> Maybe Value -> Result (List FieldFailure) (Maybe a)
readOptional name field maybeValue =
    case maybeValue of
        Just value ->
            if isEmpty value then
                Ok Nothing

            else
                readField name field value |> Result.map Just

        Nothing ->
            Ok Nothing


readField : String -> Field a -> Value -> Result (List FieldFailure) a
readField name (Field field) value =
    field.read value |> Result.mapError (List.map (Invalid name))


isEmpty : Value -> Bool
isEmpty value =
    Decode.decodeValue (Decode.null ()) value == Ok ()


{-| Apply a result of a function to a result of its argument, keeping the
errors of both.
-}
andMap : Result (List e) a -> Result (List e) (a -> b) -> Result (List e) b
andMap argument function =
    case ( function, argument ) of
        ( Ok apply, Ok value ) ->
            Ok (apply value)

        ( Err functionErrors, Err argumentErrors ) ->
            Err (functionErrors ++ argumentErrors)

        ( Err errors, Ok _ ) ->
            Err errors

        ( Ok _, Err errors ) ->
            Err errors


collect : List (Result (List e) a) -> Result (List e) (List a)
collect =
    List.foldr (\result rest -> andMap rest (Result.map (::) result)) (Ok [])



-- FIELDS


{-| A piece of text.
-}
string : Field String
string =
    primitive "a string" "strings" Decode.string


{-| A whole number.
-}
int : Field Int
int =
    Field
        { singular = "a whole number"
        , plural = "whole numbers"
        , read =
            \value ->
                case Decode.decodeValue Decode.int value of
                    Ok whole ->
                        Ok whole

                    Err _ ->
                        case Decode.decodeValue Decode.float value of
                            Ok _ ->
                                Err [ WrongType { expected = "a whole number", found = "a number with a fractional part", itemPath = [] } ]

                            Err _ ->
                                Err [ WrongType { expected = "a whole number", found = describeValue value, itemPath = [] } ]
        }


{-| Any number.
-}
float : Field Float
float =
    primitive "a number" "numbers" Decode.float


{-| `true` or `false`.
-}
bool : Field Bool
bool =
    primitive "true or false" "true or false values" Decode.bool


primitive : String -> String -> Decoder a -> Field a
primitive singular plural decoder =
    Field
        { singular = singular
        , plural = plural
        , read =
            \value ->
                Decode.decodeValue decoder value
                    |> Result.mapError (\_ -> [ WrongType { expected = singular, found = describeValue value, itemPath = [] } ])
        }


{-| A list whose items all decode with the given field.
-}
list : Field a -> Field (List a)
list (Field item) =
    let
        singular : String
        singular =
            "a list of " ++ item.plural
    in
    Field
        { singular = singular
        , plural = "lists of " ++ item.plural
        , read =
            \value ->
                case Decode.decodeValue (Decode.list Decode.value) value of
                    Err _ ->
                        Err [ WrongType { expected = singular, found = describeValue value, itemPath = [] } ]

                    Ok items ->
                        items
                            |> List.indexedMap (\index element -> item.read element |> Result.mapError (List.map (inItem index singular)))
                            |> collect
        }


inItem : Int -> String -> Failure -> Failure
inItem index listDescription failure =
    case failure of
        WrongType wrong ->
            WrongType { wrong | expected = listDescription, itemPath = index :: wrong.itemPath }

        Rejected rejected ->
            Rejected { rejected | itemPath = index :: rejected.itemPath }


{-| One of a fixed set of strings, each standing for a value.
-}
oneOf : List ( String, a ) -> Field a
oneOf choices =
    let
        allowed : String
        allowed =
            choices |> List.map (\( name, _ ) -> "`" ++ name ++ "`") |> joinWith "or"
    in
    Field
        { singular = "one of " ++ allowed
        , plural = "values, each one of " ++ allowed
        , read =
            \value ->
                case Decode.decodeValue Decode.string value of
                    Ok name ->
                        case lookup name choices of
                            Just choice ->
                                Ok choice

                            Nothing ->
                                Err [ WrongType { expected = "one of " ++ allowed, found = "`" ++ name ++ "`", itemPath = [] } ]

                    Err _ ->
                        Err [ WrongType { expected = "one of " ++ allowed, found = describeValue value, itemPath = [] } ]
        }


lookup : String -> List ( String, a ) -> Maybe a
lookup key pairs =
    case pairs of
        [] ->
            Nothing

        ( name, choice ) :: rest ->
            if name == key then
                Just choice

            else
                lookup key rest


{-| Transform a decoded value.
-}
map : (a -> b) -> Field a -> Field b
map change (Field field) =
    Field
        { singular = field.singular
        , plural = field.plural
        , read = field.read >> Result.map change
        }


{-| Check or convert a decoded value, explaining a refusal.
-}
validate : (a -> Result String b) -> Field a -> Field b
validate check (Field field) =
    Field
        { singular = field.singular
        , plural = field.plural
        , read =
            \value ->
                field.read value
                    |> Result.andThen
                        (\decoded ->
                            check decoded
                                |> Result.mapError (\message -> [ Rejected { message = message, itemPath = [] } ])
                        )
        }


{-| Decode with a `Json.Decode` decoder, for nested objects.
-}
fromDecoder : Decoder a -> Field a
fromDecoder decoder =
    Field
        { singular = "a value of the expected shape"
        , plural = "values of the expected shape"
        , read =
            \value ->
                Decode.decodeValue decoder value
                    |> Result.mapError (\error -> [ Rejected { message = Decode.errorToString error, itemPath = [] } ])
        }


{-| What a JSON value is, in plain English.
-}
describeValue : Value -> String
describeValue value =
    let
        kinds : List (Decoder String)
        kinds =
            [ Decode.null () |> Decode.map (always "empty")
            , Decode.string |> Decode.map (always "a string")
            , Decode.bool |> Decode.map (always "a true or false value")
            , Decode.float |> Decode.map (always "a number")
            , Decode.list Decode.value |> Decode.map (always "a list")
            , Decode.keyValuePairs Decode.value |> Decode.map (always "an object")
            ]
    in
    Decode.decodeValue (Decode.oneOf kinds) value
        |> Result.withDefault "something else"



-- DECODING


{-| Decode a document's frontmatter, collecting every problem.

Problems are in source order where a position is known, and the rest follow
ordered by their message, which starts with the field name.

-}
decode : Frontmatter a -> { values : Value, positions : Positions } -> Result (List Problem) a
decode (Frontmatter declaration) { values, positions } =
    case Decode.decodeValue (Decode.dict Decode.value) values of
        Err _ ->
            Err [ notAnObject ]

        Ok dict ->
            let
                unknown : List Problem
                unknown =
                    Dict.keys dict
                        |> List.filter (\key -> not (List.member key declaration.names))
                        |> List.map (unknownField declaration.names positions)
            in
            case ( declaration.read dict, unknown ) of
                ( Ok decoded, [] ) ->
                    Ok decoded

                ( result, _ ) ->
                    let
                        failures : List Problem
                        failures =
                            case result of
                                Ok _ ->
                                    []

                                Err found ->
                                    List.map (fieldProblem positions) found
                    in
                    Err (List.sortBy sortKey (unique (unknown ++ failures)))


{-| Declaring a key twice would otherwise report each of its problems twice.
-}
unique : List a -> List a
unique =
    List.foldl
        (\item kept ->
            if List.member item kept then
                kept

            else
                kept ++ [ item ]
        )
        []


notAnObject : Problem
notAnObject =
    { title = "BAD FRONTMATTER"
    , message = "The frontmatter should be a list of `key: value` lines, but it is not."
    , span = Nothing
    , hint = Nothing
    }


sortKey : Problem -> ( Int, Int, String )
sortKey problem =
    case problem.span of
        Just span ->
            ( span.start.line, span.start.column, problem.message )

        Nothing ->
            ( 2 ^ 31, 0, problem.message )


fieldProblem : Positions -> FieldFailure -> Problem
fieldProblem positions failure =
    case failure of
        Missing name ->
            { title = "MISSING FIELD"
            , message = "The `" ++ name ++ "` field is required, but this document does not have it."
            , span = Just openingFence
            , hint = reservedKeyHint name
            }

        Invalid name (WrongType wrong) ->
            { title = "BAD FRONTMATTER"
            , message =
                "The `"
                    ++ name
                    ++ "` field should be "
                    ++ wrong.expected
                    ++ ", but "
                    ++ subject wrong.itemPath
                    ++ " is "
                    ++ wrong.found
                    ++ "."
            , span = valueSpan positions name wrong.itemPath
            , hint = Nothing
            }

        Invalid name (Rejected rejected) ->
            { title = "BAD FRONTMATTER"
            , message = rejected.message
            , span = valueSpan positions name rejected.itemPath
            , hint = Nothing
            }


{-| The opening `---` is always the first line of the file, and there is no
position entry for the block, so a missing field is reported there.
-}
openingFence : Span
openingFence =
    { start = { line = 1, column = 1 }, end = { line = 1, column = 4 } }


reservedKeys : List String
reservedKeys =
    [ "slug", "date", "updated", "draft", "image" ]


reservedKeyHint : String -> Maybe String
reservedKeyHint name =
    if List.member name reservedKeys then
        Just ("Sheaf reads `" ++ name ++ "` itself, so it is not part of the frontmatter. Templates get it from the `Document` instead.")

    else
        Nothing


{-| Name an item by its whole path, innermost first: "the second item of its
first item". The path runs from the outermost list inwards.
-}
subject : List Int -> String
subject itemPath =
    case itemPath of
        [] ->
            "it"

        outermost :: inner ->
            (List.map (\index -> "the " ++ ordinal (index + 1) ++ " item") (List.reverse inner)
                ++ [ "its " ++ ordinal (outermost + 1) ++ " item" ]
            )
                |> String.join " of "


ordinal : Int -> String
ordinal number =
    case number of
        1 ->
            "first"

        2 ->
            "second"

        3 ->
            "third"

        4 ->
            "fourth"

        5 ->
            "fifth"

        6 ->
            "sixth"

        7 ->
            "seventh"

        8 ->
            "eighth"

        9 ->
            "ninth"

        10 ->
            "tenth"

        _ ->
            String.fromInt number ++ ordinalSuffix number


ordinalSuffix : Int -> String
ordinalSuffix number =
    if List.member (modBy 100 number) [ 11, 12, 13 ] then
        "th"

    else
        case modBy 10 number of
            1 ->
                "st"

            2 ->
                "nd"

            3 ->
                "rd"

            _ ->
                "th"


{-| The span of the value itself, or of the nearest enclosing item or field
that has an entry when the value has none of its own.
-}
valueSpan : Positions -> String -> List Int -> Maybe Span
valueSpan positions name itemPath =
    List.range 0 (List.length itemPath)
        |> List.reverse
        |> List.filterMap
            (\depth ->
                Dict.get (String.join "." (name :: List.map String.fromInt (List.take depth itemPath))) positions
            )
        |> List.head
        |> Maybe.map .value



-- UNKNOWN FIELDS


unknownField : List String -> Positions -> String -> Problem
unknownField declared positions key =
    { title = "UNKNOWN FIELD"
    , message = "This document has a `" ++ key ++ "` field, but its collection does not declare one."
    , span =
        Dict.get key positions
            |> Maybe.andThen (\position -> position.key |> orElse (Just position.value))
    , hint = unknownFieldHint declared key
    }


orElse : Maybe a -> Maybe a -> Maybe a
orElse fallback maybe =
    case maybe of
        Just _ ->
            maybe

        Nothing ->
            fallback


unknownFieldHint : List String -> String -> Maybe String
unknownFieldHint declared key =
    case suggestions declared key of
        [] ->
            case declared of
                [] ->
                    Nothing

                _ ->
                    Just ("The fields declared here are " ++ joinWith "and" (List.map backticked declared) ++ ".")

        [ only ] ->
            Just ("Did you mean `" ++ only ++ "`?")

        several ->
            Just ("Did you mean one of these?\n\n" ++ String.join "\n" (List.map (\name -> "    " ++ name) several))


backticked : String -> String
backticked name =
    "`" ++ name ++ "`"


{-| Up to three declared names close to `key`, closest first.

A name is close when it is within a third of the typed length in edits, but
never fewer than two: a transposition such as `tilte` costs two edits, and a
single edit would miss it. It is never the whole word, so short keys such as
`a` do not suggest every other short name.

-}
suggestions : List String -> String -> List String
suggestions declared key =
    let
        typed : String
        typed =
            String.toLower key

        allowed : Int
        allowed =
            max 2 (String.length typed // 3)
    in
    declared
        |> List.map (\name -> ( editDistance typed (String.toLower name), name ))
        |> List.filter (\( distance, _ ) -> distance <= allowed && distance < String.length typed)
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
