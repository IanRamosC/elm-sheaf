module Sheaf.FrontmatterTest exposing (suite)

import Dict
import Expect
import Json.Decode as Decode
import Json.Encode as Encode
import Sheaf.Frontmatter as Frontmatter exposing (Frontmatter)
import Sheaf.Internal.Frontmatter as Internal exposing (Problem)
import Sheaf.Internal.Protocol exposing (Span)
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Sheaf.Frontmatter"
        [ validTests
        , unknownFieldTests
        , missingFieldTests
        , badFrontmatterTests
        , fieldTests
        , collectingTests
        ]



-- DECLARATIONS


type alias Meta =
    { title : String
    , tags : List String
    , summary : Maybe String
    }


meta : Frontmatter Meta
meta =
    Frontmatter.succeed Meta
        |> Frontmatter.required "title" Frontmatter.string
        |> Frontmatter.withDefault "tags" [] (Frontmatter.list Frontmatter.string)
        |> Frontmatter.optional "summary" Frontmatter.string


span : Int -> Int -> Int -> Span
span line from to =
    { start = { line = line, column = from }, end = { line = line, column = to } }


{-| The span of the opening `---`, where a missing field is reported.
-}
openingFence : Span
openingFence =
    span 1 1 4


decodeWith : Frontmatter a -> List ( String, Encode.Value ) -> List ( String, Span ) -> Result (List Problem) a
decodeWith declaration fields positions =
    Internal.decode declaration
        { values = Encode.object fields
        , positions =
            positions
                |> List.map (\( path, valueSpan ) -> ( path, { key = Nothing, value = valueSpan } ))
                |> Dict.fromList
        }


problemsOf : Result (List Problem) a -> List Problem
problemsOf result =
    case result of
        Ok _ ->
            []

        Err problems ->
            problems



-- TESTS


validTests : Test
validTests =
    describe "a valid file"
        [ test "decodes to the record" <|
            \_ ->
                decodeWith meta
                    [ ( "title", Encode.string "Hello" )
                    , ( "tags", Encode.list Encode.string [ "elm" ] )
                    , ( "summary", Encode.string "Hi" )
                    ]
                    []
                    |> Expect.equal (Ok { title = "Hello", tags = [ "elm" ], summary = Just "Hi" })
        , test "uses the default and Nothing for absent optional fields" <|
            \_ ->
                decodeWith meta [ ( "title", Encode.string "Hello" ) ] []
                    |> Expect.equal (Ok { title = "Hello", tags = [], summary = Nothing })
        , test "treats an empty value as absent for optional fields" <|
            \_ ->
                decodeWith meta [ ( "title", Encode.string "Hello" ), ( "summary", Encode.null ) ] []
                    |> Expect.equal (Ok { title = "Hello", tags = [], summary = Nothing })
        ]


unknownFieldTests : Test
unknownFieldTests =
    describe "UNKNOWN FIELD"
        [ test "is located at the key and suggests the closest declared field" <|
            \_ ->
                let
                    positions : Internal.Positions
                    positions =
                        Dict.fromList
                            [ ( "sumary", { key = Just (span 3 1 7), value = span 3 9 10 } ) ]
                in
                Internal.decode meta
                    { values = Encode.object [ ( "title", Encode.string "T" ), ( "sumary", Encode.string "x" ) ]
                    , positions = positions
                    }
                    |> problemsOf
                    |> Expect.equal
                        [ { title = "UNKNOWN FIELD"
                          , message = "This document has a `sumary` field, but its collection does not declare one."
                          , span = Just (span 3 1 7)
                          , hint = Just "Did you mean `summary`?"
                          }
                        ]
        , test "lists up to three suggestions, closest first" <|
            \_ ->
                let
                    close : Frontmatter ()
                    close =
                        Frontmatter.succeed (\_ _ _ _ _ -> ())
                            |> Frontmatter.optional "cat" Frontmatter.string
                            |> Frontmatter.optional "car" Frontmatter.string
                            |> Frontmatter.optional "cart" Frontmatter.string
                            |> Frontmatter.optional "care" Frontmatter.string
                            |> Frontmatter.optional "dog" Frontmatter.string
                in
                decodeWith close [ ( "carts", Encode.string "" ) ] []
                    |> problemsOf
                    |> List.map .hint
                    |> Expect.equal [ Just "Did you mean one of these?\n\n    cart\n    cat\n    car" ]
        , test "lists the declared fields when nothing is close" <|
            \_ ->
                decodeWith meta [ ( "title", Encode.string "T" ), ( "layout", Encode.string "x" ) ] []
                    |> problemsOf
                    |> List.map .hint
                    |> Expect.equal [ Just "The fields declared here are `title`, `tags` and `summary`." ]
        ]


missingFieldTests : Test
missingFieldTests =
    describe "MISSING FIELD"
        [ test "is located at the opening fence" <|
            \_ ->
                decodeWith meta [] []
                    |> problemsOf
                    |> Expect.equal
                        [ { title = "MISSING FIELD"
                          , message = "The `title` field is required, but this document does not have it."
                          , span = Just openingFence
                          , hint = Nothing
                          }
                        ]
        , test "explains reserved keys" <|
            \_ ->
                let
                    withDate : Frontmatter String
                    withDate =
                        Frontmatter.succeed identity
                            |> Frontmatter.required "date" Frontmatter.string
                in
                decodeWith withDate [] []
                    |> problemsOf
                    |> List.map .hint
                    |> Expect.equal
                        [ Just "Sheaf reads `date` itself, so it is not part of the frontmatter. Templates get it from the `Document` instead." ]
        ]


badFrontmatterTests : Test
badFrontmatterTests =
    describe "BAD FRONTMATTER"
        [ test "locates a wrong list item and names it by ordinal" <|
            \_ ->
                decodeWith meta
                    [ ( "title", Encode.string "T" )
                    , ( "tags", Encode.list identity [ Encode.string "elm", Encode.int 42 ] )
                    ]
                    [ ( "tags", span 4 7 16 ), ( "tags.0", span 4 8 11 ), ( "tags.1", span 4 13 15 ) ]
                    |> problemsOf
                    |> Expect.equal
                        [ { title = "BAD FRONTMATTER"
                          , message = "The `tags` field should be a list of strings, but its second item is a number."
                          , span = Just (span 4 13 15)
                          , hint = Nothing
                          }
                        ]
        , test "reports every bad item" <|
            \_ ->
                decodeWith meta
                    [ ( "title", Encode.string "T" )
                    , ( "tags", Encode.list identity [ Encode.bool True, Encode.string "x", Encode.null ] )
                    ]
                    []
                    |> problemsOf
                    |> List.map .message
                    |> Expect.equal
                        [ "The `tags` field should be a list of strings, but its first item is a true or false value."
                        , "The `tags` field should be a list of strings, but its third item is empty."
                        ]
        , test "names the whole path of a nested list item" <|
            \_ ->
                decodeWith
                    (Frontmatter.succeed identity
                        |> Frontmatter.required "grid" (Frontmatter.list (Frontmatter.list Frontmatter.string))
                    )
                    [ ( "grid"
                      , Encode.list (Encode.list identity)
                            [ [ Encode.string "a" ], [ Encode.string "b", Encode.int 3 ] ]
                      )
                    ]
                    [ ( "grid", span 2 7 20 ), ( "grid.1", span 2 12 19 ) ]
                    |> problemsOf
                    |> Expect.equal
                        [ { title = "BAD FRONTMATTER"
                          , message = "The `grid` field should be a list of lists of strings, but the second item of its second item is a number."
                          , span = Just (span 2 12 19)
                          , hint = Nothing
                          }
                        ]
        , test "names a nested item outermost-last, whatever its position" <|
            \_ ->
                let
                    grid : Frontmatter (List (List String))
                    grid =
                        Frontmatter.succeed identity
                            |> Frontmatter.required "grid" (Frontmatter.list (Frontmatter.list Frontmatter.string))
                in
                decodeWith grid
                    [ ( "grid", Encode.list (Encode.list identity) [ [ Encode.string "a", Encode.int 3 ] ] ) ]
                    []
                    |> problemsOf
                    |> List.map .message
                    |> Expect.equal
                        [ "The `grid` field should be a list of lists of strings, but the second item of its first item is a number." ]
        , test "names a three-level item from the inside out" <|
            \_ ->
                let
                    cube : Frontmatter (List (List (List String)))
                    cube =
                        Frontmatter.succeed identity
                            |> Frontmatter.required "cube" (Frontmatter.list (Frontmatter.list (Frontmatter.list Frontmatter.string)))
                in
                decodeWith cube
                    [ ( "cube"
                      , Encode.list identity
                            [ Encode.list identity []
                            , Encode.list identity
                                [ Encode.list Encode.string [ "a" ]
                                , Encode.list Encode.int [ 3 ]
                                ]
                            ]
                      )
                    ]
                    []
                    |> problemsOf
                    |> List.map .message
                    |> Expect.equal
                        [ "The `cube` field should be a list of lists of lists of strings, but the first item of the second item of its second item is a number." ]
        , test "uses the right suffix for ordinals past ten" <|
            \_ ->
                let
                    badItems : List Int
                    badItems =
                        [ 11, 21, 22, 23, 111 ]

                    items : List Encode.Value
                    items =
                        List.range 1 111
                            |> List.map
                                (\number ->
                                    if List.member number badItems then
                                        Encode.int number

                                    else
                                        Encode.string "x"
                                )
                in
                decodeWith meta [ ( "title", Encode.string "T" ), ( "tags", Encode.list identity items ) ] []
                    |> problemsOf
                    |> List.map .message
                    |> List.sort
                    |> Expect.equal
                        ([ "11th", "21st", "22nd", "23rd", "111th" ]
                            |> List.map (\ordinal -> "The `tags` field should be a list of strings, but its " ++ ordinal ++ " item is a number.")
                            |> List.sort
                        )
        , test "a key declared twice is reported once" <|
            \_ ->
                let
                    twice : Frontmatter ( String, String )
                    twice =
                        Frontmatter.succeed Tuple.pair
                            |> Frontmatter.required "cat" Frontmatter.string
                            |> Frontmatter.required "cat" Frontmatter.string
                in
                decodeWith twice [ ( "cat", Encode.int 1 ), ( "cta", Encode.int 2 ) ] []
                    |> problemsOf
                    |> List.map (\problem -> ( problem.title, problem.hint ))
                    |> Expect.equal
                        [ ( "BAD FRONTMATTER", Nothing )
                        , ( "UNKNOWN FIELD", Just "Did you mean `cat`?" )
                        ]
        , test "describes a value that is not a list" <|
            \_ ->
                decodeWith meta [ ( "title", Encode.string "T" ), ( "tags", Encode.string "elm" ) ] [ ( "tags", span 2 7 12 ) ]
                    |> problemsOf
                    |> Expect.equal
                        [ { title = "BAD FRONTMATTER"
                          , message = "The `tags` field should be a list of strings, but it is a string."
                          , span = Just (span 2 7 12)
                          , hint = Nothing
                          }
                        ]
        , test "has no span when the value has no position entry" <|
            \_ ->
                decodeWith meta [ ( "title", Encode.null ) ] []
                    |> problemsOf
                    |> Expect.equal
                        [ { title = "BAD FRONTMATTER"
                          , message = "The `title` field should be a string, but it is empty."
                          , span = Nothing
                          , hint = Nothing
                          }
                        ]
        , test "describes lists and objects" <|
            \_ ->
                decodeWith meta
                    [ ( "title", Encode.list Encode.int [] ), ( "summary", Encode.object [] ) ]
                    []
                    |> problemsOf
                    |> List.map .message
                    |> Expect.equal
                        [ "The `summary` field should be a string, but it is an object."
                        , "The `title` field should be a string, but it is a list."
                        ]
        ]


type Severity
    = Warning
    | Info


fieldTests : Test
fieldTests =
    describe "fields"
        [ test "oneOf lists the allowed values" <|
            \_ ->
                decodeWith
                    (Frontmatter.succeed identity
                        |> Frontmatter.required "kind" (Frontmatter.oneOf [ ( "warning", Warning ), ( "info", Info ) ])
                    )
                    [ ( "kind", Encode.string "danger" ) ]
                    [ ( "kind", span 2 7 13 ) ]
                    |> problemsOf
                    |> Expect.equal
                        [ { title = "BAD FRONTMATTER"
                          , message = "The `kind` field should be one of `warning` or `info`, but it is `danger`."
                          , span = Just (span 2 7 13)
                          , hint = Nothing
                          }
                        ]
        , test "oneOf maps a matching value" <|
            \_ ->
                decodeWith
                    (Frontmatter.succeed identity
                        |> Frontmatter.required "kind" (Frontmatter.oneOf [ ( "warning", Warning ), ( "info", Info ) ])
                    )
                    [ ( "kind", Encode.string "info" ) ]
                    []
                    |> Expect.equal (Ok Info)
        , test "validate reports the user's message" <|
            \_ ->
                decodeWith
                    (Frontmatter.succeed identity
                        |> Frontmatter.required "title"
                            (Frontmatter.string
                                |> Frontmatter.validate
                                    (\title ->
                                        if String.length title < 5 then
                                            Ok title

                                        else
                                            Err "must be under 5 characters"
                                    )
                            )
                    )
                    [ ( "title", Encode.string "too long" ) ]
                    [ ( "title", span 1 8 16 ) ]
                    |> problemsOf
                    |> Expect.equal
                        [ { title = "BAD FRONTMATTER"
                          , message = "must be under 5 characters"
                          , span = Just (span 1 8 16)
                          , hint = Nothing
                          }
                        ]
        , test "map transforms a decoded value" <|
            \_ ->
                decodeWith
                    (Frontmatter.succeed identity
                        |> Frontmatter.required "title" (Frontmatter.map String.toUpper Frontmatter.string)
                    )
                    [ ( "title", Encode.string "hi" ) ]
                    []
                    |> Expect.equal (Ok "HI")
        , test "int, float and bool decode numbers and booleans" <|
            \_ ->
                decodeWith
                    (Frontmatter.succeed (\a b c -> ( a, b, c ))
                        |> Frontmatter.required "a" Frontmatter.int
                        |> Frontmatter.required "b" Frontmatter.float
                        |> Frontmatter.required "c" Frontmatter.bool
                    )
                    [ ( "a", Encode.int 3 ), ( "b", Encode.float 1.5 ), ( "c", Encode.bool True ) ]
                    []
                    |> Expect.equal (Ok ( 3, 1.5, True ))
        , test "int rejects a fractional number" <|
            \_ ->
                decodeWith
                    (Frontmatter.succeed identity |> Frontmatter.required "count" Frontmatter.int)
                    [ ( "count", Encode.float 1.5 ) ]
                    []
                    |> problemsOf
                    |> List.map .message
                    |> Expect.equal [ "The `count` field should be a whole number, but it is a number with a fractional part." ]
        , test "fromDecoder accepts a nested object with any keys" <|
            \_ ->
                decodeWith
                    (Frontmatter.succeed identity
                        |> Frontmatter.required "author"
                            (Frontmatter.fromDecoder (Decode.field "name" Decode.string))
                    )
                    [ ( "author", Encode.object [ ( "name", Encode.string "Ian" ), ( "anything", Encode.int 1 ) ] ) ]
                    []
                    |> Expect.equal (Ok "Ian")
        , test "fromDecoder failures use the decoder's explanation" <|
            \_ ->
                decodeWith
                    (Frontmatter.succeed identity
                        |> Frontmatter.required "author" (Frontmatter.fromDecoder (Decode.field "name" Decode.string))
                    )
                    [ ( "author", Encode.object [] ) ]
                    []
                    |> problemsOf
                    |> List.map .title
                    |> Expect.equal [ "BAD FRONTMATTER" ]
        ]


collectingTests : Test
collectingTests =
    describe "all problems at once"
        [ test "an unknown key, a missing field and a wrong type give three problems in source order" <|
            \_ ->
                Internal.decode meta
                    { values =
                        Encode.object
                            [ ( "sumary", Encode.string "x" )
                            , ( "tags", Encode.string "elm" )
                            ]
                    , positions =
                        Dict.fromList
                            [ ( "sumary", { key = Just (span 2 1 7), value = span 2 9 10 } )
                            , ( "tags", { key = Just (span 3 1 5), value = span 3 7 10 } )
                            ]
                    }
                    |> problemsOf
                    |> List.map (\problem -> ( problem.title, problem.span ))
                    |> Expect.equal
                        [ ( "MISSING FIELD", Just openingFence )
                        , ( "UNKNOWN FIELD", Just (span 2 1 7) )
                        , ( "BAD FRONTMATTER", Just (span 3 7 10) )
                        ]
        , test "problems without a position come last, ordered by field name" <|
            \_ ->
                decodeWith meta [ ( "title", Encode.int 1 ), ( "tags", Encode.int 2 ), ( "summary", Encode.int 3 ) ] []
                    |> problemsOf
                    |> List.map .message
                    |> Expect.equal
                        [ "The `summary` field should be a string, but it is a number."
                        , "The `tags` field should be a list of strings, but it is a number."
                        , "The `title` field should be a string, but it is a number."
                        ]
        , test "frontmatter that is not an object is one problem" <|
            \_ ->
                Internal.decode meta { values = Encode.list Encode.int [ 1 ], positions = Dict.empty }
                    |> problemsOf
                    |> List.map .title
                    |> Expect.equal [ "BAD FRONTMATTER" ]
        ]
