module Sheaf.Internal.Group exposing (Group, Problem, group, diagnostic)

{-| Grouping documents by a frontmatter value, such as their tags.

Values are grouped by the slug the host computed for each, because `elm/core`
cannot normalise Unicode. A value the host did not slug, a slug with nothing
in it, and different words that share a slug are problems, and a route with
any of them writes no pages.

@docs Group, Problem, group, diagnostic

-}

import Dict exposing (Dict)
import Json.Decode as Decode
import Sheaf.Internal.Protocol exposing (Diagnostic, Document, GroupSlug, Severity(..), Span)


{-| The items that have a value with this slug, in the order they were given,
and the name the group is shown with.
-}
type alias Group item =
    { slug : String
    , name : String
    , items : List item
    }


{-| Why values cannot be grouped. Routes that group the same documents find
the same problems, which are reported once.
-}
type Problem
    = MissingSlug String
    | EmptySlug { value : String, sourcePath : String, span : Maybe Span }
    | Collision { slug : String, spellings : List ( String, List String ) }


{-| One document using one value with a slug.
-}
type alias Use item =
    { item : item
    , value : String
    , folded : String
    }


{-| The groups of the items, ordered by slug, and what kept any value out of
them. An item is in a group once, however many of its values have that slug.

A group's name is its most common spelling, and of equally common ones the
first by code point, so that it does not change from one build to the next.

-}
group : Dict String GroupSlug -> List ( { a | document : Document }, List String ) -> { groups : List (Group { a | document : Document }), problems : List Problem }
group slugs valued =
    let
        placed : List (Result Problem ( String, Use { a | document : Document } ))
        placed =
            List.concatMap (\( item, values ) -> List.map (place slugs item) (unique values)) valued

        bySlug : List ( String, List (Use { a | document : Document }) )
        bySlug =
            placed
                |> List.filterMap Result.toMaybe
                |> List.foldr (\( slug, use ) -> Dict.update slug (\uses -> Just (use :: Maybe.withDefault [] uses))) Dict.empty
                |> Dict.toList
                |> List.sortWith (\( a, _ ) ( b, _ ) -> byCodePoint a b)
    in
    { groups = List.map (\( slug, uses ) -> groupOf slug uses) bySlug
    , problems =
        unique (List.filterMap problemOf placed)
            ++ List.filterMap (\( slug, uses ) -> collisionOf slug uses) bySlug
    }


place : Dict String GroupSlug -> { a | document : Document } -> String -> Result Problem ( String, Use { a | document : Document } )
place slugs item value =
    case Dict.get value slugs of
        Nothing ->
            Err (MissingSlug value)

        Just { slug, folded } ->
            if slug == "" then
                Err (EmptySlug { value = value, sourcePath = item.document.sourcePath, span = spanOf value item.document })

            else
                Ok ( slug, { item = item, value = value, folded = folded } )


groupOf : String -> List (Use { a | document : Document }) -> Group { a | document : Document }
groupOf slug uses =
    let
        spellings : List ( String, Int )
        spellings =
            List.map (\spelling -> ( spelling, List.length (List.filter (\use -> use.value == spelling) uses) ))
                (unique (List.map .value uses))

        name : String
        name =
            spellings
                |> List.sortWith (\( a, countA ) ( b, countB ) -> compareBoth (compare countB countA) (byCodePoint a b))
                |> List.head
                |> Maybe.map Tuple.first
                |> Maybe.withDefault slug
    in
    { slug = slug
    , name = name
    , items = uniqueBy (.document >> .id) (List.map .item uses)
    }


{-| The host folds case, accents, spaces, dashes and underscores the same way
for both, so values with different folds share a slug only by accident of
their other punctuation, as `C` and `C++` do.
-}
collisionOf : String -> List (Use { a | document : Document }) -> Maybe Problem
collisionOf slug uses =
    case unique (List.map .folded uses) of
        _ :: _ :: _ ->
            Just
                (Collision
                    { slug = slug
                    , spellings =
                        unique (List.map .value uses)
                            |> List.sortWith byCodePoint
                            |> List.map
                                (\spelling ->
                                    ( spelling
                                    , uses
                                        |> List.filter (\use -> use.value == spelling)
                                        |> List.map (.item >> .document >> .sourcePath)
                                    )
                                )
                    }
                )

        _ ->
            Nothing


problemOf : Result Problem a -> Maybe Problem
problemOf result =
    case result of
        Ok _ ->
            Nothing

        Err problem ->
            Just problem


compareBoth : Order -> Order -> Order
compareBoth first second =
    case first of
        EQ ->
            second

        _ ->
            first


{-| JavaScript compares strings by UTF-16 code unit, which puts some
characters outside the Basic Multilingual Plane before others inside it.
-}
byCodePoint : String -> String -> Order
byCodePoint a b =
    compare (List.map Char.toCode (String.toList a)) (List.map Char.toCode (String.toList b))


unique : List a -> List a
unique =
    uniqueBy identity


uniqueBy : (a -> key) -> List a -> List a
uniqueBy key items =
    List.foldl
        (\item ( seen, kept ) ->
            if List.member (key item) seen then
                ( seen, kept )

            else
                ( key item :: seen, item :: kept )
        )
        ( [], [] )
        items
        |> Tuple.second
        |> List.reverse



-- DIAGNOSTICS


{-| The diagnostic of a problem found by the route named `routeName`.
-}
diagnostic : String -> Problem -> Diagnostic
diagnostic routeName problem =
    case problem of
        MissingSlug value ->
            { severity = Error
            , title = "MISSING SLUG"
            , message = "The route `" ++ routeName ++ "` groups documents by the value `" ++ value ++ "`, which has no slug."
            , sourcePath = Nothing
            , span = Nothing
            , hint = Just "Group values must come from frontmatter as written; Sheaf computes their slugs before Elm runs."
            }

        EmptySlug { value, sourcePath, span } ->
            { severity = Error
            , title = "EMPTY GROUP SLUG"
            , message = "The value `" ++ value ++ "` has no letters or digits, so it has no slug to make a group page from."
            , sourcePath = Just sourcePath
            , span = span
            , hint = Just "Use a value with at least one letter or digit, or remove it."
            }

        Collision { slug, spellings } ->
            { severity = Error
            , title = "GROUP COLLISION"
            , message =
                "The values "
                    ++ joinAnd (List.map (\( spelling, _ ) -> "`" ++ spelling ++ "`") spellings)
                    ++ " have the same slug, `"
                    ++ slug
                    ++ "`, but are different words, so they cannot share a group:\n\n"
                    ++ String.join "\n" (List.map (\( spelling, paths ) -> "    `" ++ spelling ++ "` in " ++ String.join ", " paths) spellings)
            , sourcePath = Nothing
            , span = Nothing
            , hint = Just "Spell them the same way if they are the same thing, or rename one of them."
            }


joinAnd : List String -> String
joinAnd items =
    case List.reverse items of
        last :: ((_ :: _) as before) ->
            String.join ", " (List.reverse before) ++ " and " ++ last

        _ ->
            String.concat items


{-| Where a value is written in a document. The value the route grouped by
may not be written anywhere, so it falls back to the whole frontmatter.
-}
spanOf : String -> Document -> Maybe Span
spanOf value document =
    case pathTo value "" document.frontmatter |> Maybe.andThen (\path -> Dict.get path document.frontmatterPositions) of
        Just position ->
            Just position.value

        Nothing ->
            Maybe.map .value (Dict.get "" document.frontmatterPositions)


{-| The first path, in document order, to a string equal to `value` in the
frontmatter, the way the host names paths: `tags`, `tags.1`.
-}
pathTo : String -> String -> Decode.Value -> Maybe String
pathTo value path json =
    let
        inside : List ( String, Decode.Value ) -> Maybe String
        inside children =
            case children of
                [] ->
                    Nothing

                ( key, child ) :: rest ->
                    case pathTo value (joinPath path key) child of
                        Just found ->
                            Just found

                        Nothing ->
                            inside rest
    in
    case Decode.decodeValue frontmatterValue json of
        Ok (Text text) ->
            if text == value then
                Just path

            else
                Nothing

        Ok (Items items) ->
            inside (List.indexedMap (\index item -> ( String.fromInt index, item )) items)

        Ok (Fields fields) ->
            inside fields

        Err _ ->
            Nothing


type FrontmatterValue
    = Text String
    | Items (List Decode.Value)
    | Fields (List ( String, Decode.Value ))


frontmatterValue : Decode.Decoder FrontmatterValue
frontmatterValue =
    Decode.oneOf
        [ Decode.map Text Decode.string
        , Decode.map Items (Decode.list Decode.value)
        , Decode.map Fields (Decode.keyValuePairs Decode.value)
        ]


joinPath : String -> String -> String
joinPath parent child =
    if parent == "" then
        child

    else
        parent ++ "." ++ child
