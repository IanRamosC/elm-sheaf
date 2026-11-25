module Sheaf.Internal.Component exposing
    ( Component, Attributes, Value, Kind(..), Directive, Problem
    , container, leaf
    , succeed, required, optional, withDefault
    , string, int, oneOf, map, validate
    , byName, use, siteProblems
    )

{-| Components and the attribute decoders behind `Sheaf.Component`, plus what
the renderer needs: finding a directive's component and checking the site's
components once per build.

@docs Component, Attributes, Value, Kind, Directive, Problem
@docs container, leaf
@docs succeed, required, optional, withDefault
@docs string, int, oneOf, map, validate
@docs byName, use, siteProblems

-}

import Dict exposing (Dict)
import Sheaf.Html exposing (Html)
import Sheaf.Internal.Hint as Hint
import Sheaf.Internal.Protocol exposing (Diagnostic, Severity(..))
import Sheaf.Internal.Results as Results



-- TYPES


{-| A name, the attributes it takes and its view, already given the decoded
attributes. A leaf's view ignores the children, which it never has.
-}
type Component
    = Component
        { name : String
        , kind : Kind
        , attributeNames : List String
        , view : Dict String String -> Result (List Failure) (List Html -> Html)
        }


{-| A container wraps Markdown, `:::name` … `:::`; a leaf stands on one line,
`::name`.
-}
type Kind
    = Container
    | Leaf


{-| A record decoder that knows the names of its attributes.
-}
type Attributes a
    = Attributes
        { names : List String
        , read : Dict String String -> Result (List Failure) a
        }


{-| How to decode the text of one attribute. `expected` says what it accepts,
such as "a whole number".
-}
type Value a
    = Value
        { expected : String
        , read : String -> Result Refusal a
        }


type Refusal
    = Unexpected
    | Refused String


type Failure
    = Missing String
    | Invalid { name : String, expected : String, written : String }
    | Rejected String


{-| A directive as written in a document.
-}
type alias Directive =
    { kind : Kind
    , name : String
    , attributes : List ( String, String )
    }


{-| Something wrong with a directive. The renderer knows where it is.
-}
type alias Problem =
    { title : String
    , message : String
    , hint : Maybe String
    }



-- COMPONENTS


{-| A component that wraps Markdown.
-}
container : String -> Attributes a -> (a -> List Html -> Html) -> Component
container name (Attributes attributes) view =
    Component
        { name = name
        , kind = Container
        , attributeNames = attributes.names
        , view = attributes.read >> Result.map view
        }


{-| A component on a line of its own.
-}
leaf : String -> Attributes a -> (a -> Html) -> Component
leaf name (Attributes attributes) view =
    Component
        { name = name
        , kind = Leaf
        , attributeNames = attributes.names
        , view = attributes.read >> Result.map (\decoded _ -> view decoded)
        }



-- ATTRIBUTES


{-| A decoder for a record with no attributes yet.
-}
succeed : a -> Attributes a
succeed value =
    Attributes { names = [], read = \_ -> Ok value }


{-| An attribute that must be written.
-}
required : String -> Value a -> Attributes (a -> b) -> Attributes b
required name value =
    addAttribute name <|
        \written ->
            case written of
                Just text ->
                    readValue name value text

                Nothing ->
                    Err [ Missing name ]


{-| An attribute that may be left out.
-}
optional : String -> Value a -> Attributes (Maybe a -> b) -> Attributes b
optional name value =
    addAttribute name (readOptional name value)


{-| An attribute that may be left out, replaced by a default.
-}
withDefault : String -> a -> Value a -> Attributes (a -> b) -> Attributes b
withDefault name default value =
    addAttribute name (readOptional name value >> Result.map (Maybe.withDefault default))


addAttribute : String -> (Maybe String -> Result (List Failure) a) -> Attributes (a -> b) -> Attributes b
addAttribute name readWritten (Attributes previous) =
    Attributes
        { names =
            if List.member name previous.names then
                previous.names

            else
                previous.names ++ [ name ]
        , read = \written -> andMap (readWritten (Dict.get name written)) (previous.read written)
        }


readOptional : String -> Value a -> Maybe String -> Result (List Failure) (Maybe a)
readOptional name value written =
    case written of
        Just text ->
            readValue name value text |> Result.map Just

        Nothing ->
            Ok Nothing


readValue : String -> Value a -> String -> Result (List Failure) a
readValue name (Value value) written =
    case value.read written of
        Ok decoded ->
            Ok decoded

        Err Unexpected ->
            Err [ Invalid { name = name, expected = value.expected, written = written } ]

        Err (Refused message) ->
            Err [ Rejected message ]


{-| Apply a result of a function to a result of its argument, keeping the
failures of both.
-}
andMap : Result (List e) a -> Result (List e) (a -> b) -> Result (List e) b
andMap argument function =
    case ( function, argument ) of
        ( Ok apply, Ok value ) ->
            Ok (apply value)

        ( Err functionFailures, Err argumentFailures ) ->
            Err (functionFailures ++ argumentFailures)

        ( Err failures, Ok _ ) ->
            Err failures

        ( Ok _, Err failures ) ->
            Err failures



-- VALUES


{-| The text as written.
-}
string : Value String
string =
    Value { expected = "text", read = Ok }


{-| A whole number.
-}
int : Value Int
int =
    Value { expected = "a whole number", read = String.toInt >> Result.fromMaybe Unexpected }


{-| One of a fixed set of texts, each standing for a value.
-}
oneOf : List ( String, a ) -> Value a
oneOf choices =
    Value
        { expected = "one of " ++ String.join ", " (List.map (\( name, _ ) -> "`" ++ name ++ "`") choices)
        , read =
            \written ->
                choices
                    |> List.filter (\( name, _ ) -> name == written)
                    |> List.head
                    |> Maybe.map Tuple.second
                    |> Result.fromMaybe Unexpected
        }


{-| Transform a decoded value.
-}
map : (a -> b) -> Value a -> Value b
map change (Value value) =
    Value { expected = value.expected, read = value.read >> Result.map change }


{-| Check or convert a decoded value, explaining a refusal.
-}
validate : (a -> Result String b) -> Value a -> Value b
validate check (Value value) =
    Value
        { expected = value.expected
        , read = value.read >> Result.andThen (check >> Result.mapError Refused)
        }



-- RENDERING


{-| The components by name, for looking up each directive. Of two with one
name the last is kept, but `siteProblems` reports them, so no page is built
with either.
-}
byName : List Component -> Dict String Component
byName components =
    components
        |> List.map (\((Component component) as whole) -> ( component.name, whole ))
        |> Dict.fromList


{-| The view of a directive's component, given its decoded attributes, or
every problem of the directive.
-}
use : Dict String Component -> Directive -> Result (List Problem) (List Html -> Html)
use components directive =
    case Dict.get directive.name components of
        Nothing ->
            Err [ unknownComponent (Dict.keys components) directive ]

        Just (Component component) ->
            if component.kind /= directive.kind then
                Err [ wrongKind component.kind directive.name ]

            else
                let
                    unknown : List Problem
                    unknown =
                        directive.attributes
                            |> List.map Tuple.first
                            |> List.filter (\name -> not (List.member name component.attributeNames))
                            |> List.map (unknownAttribute component.attributeNames directive.name)
                in
                case ( component.view (Dict.fromList directive.attributes), unknown ) of
                    ( Ok view, [] ) ->
                        Ok view

                    ( Ok _, _ ) ->
                        Err unknown

                    ( Err failures, _ ) ->
                        Err (List.map (failureProblem directive) failures ++ unknown)


unknownComponent : List String -> Directive -> Problem
unknownComponent known directive =
    let
        addIt : String
        addIt =
            "Add it to the site's `components`, such as `" ++ constructorOf directive.kind ++ " \"" ++ directive.name ++ "\" …`."
    in
    { title = "UNKNOWN COMPONENT"
    , message = "This document uses a component named `" ++ directive.name ++ "`, but the site has no component with that name."
    , hint =
        -- Listing every component would not help someone who has yet to add one.
        Hint.didYouMean (\_ -> addIt) known directive.name
            |> Maybe.withDefault addIt
            |> Just
    }


constructorOf : Kind -> String
constructorOf kind =
    case kind of
        Container ->
            "Component.container"

        Leaf ->
            "Component.leaf"


wrongKind : Kind -> String -> Problem
wrongKind declared name =
    let
        quoted : String
        quoted =
            "`" ++ name ++ "`"
    in
    { title = "WRONG COMPONENT KIND"
    , message =
        case declared of
            Leaf ->
                quoted ++ " is a leaf component, written on one line as `::" ++ name ++ "{…}`, but here it is used as a container, `:::" ++ name ++ "`."

            Container ->
                quoted ++ " is a container component, written around its content as `:::" ++ name ++ "{…}` and `:::`, but here it is used as a leaf, `::" ++ name ++ "`."
    , hint = Nothing
    }


unknownAttribute : List String -> String -> String -> Problem
unknownAttribute known component name =
    { title = "UNKNOWN ATTRIBUTE"
    , message = "`" ++ component ++ "` has no attribute named `" ++ name ++ "`."
    , hint =
        Hint.didYouMean (\names -> "The attributes of `" ++ component ++ "` are " ++ names ++ ".") known name
            |> Maybe.withDefault ("`" ++ component ++ "` takes no attributes.")
            |> Just
    }


failureProblem : Directive -> Failure -> Problem
failureProblem directive failure =
    case failure of
        Missing name ->
            { title = "MISSING ATTRIBUTE"
            , message = "This `" ++ directive.name ++ "` has no `" ++ name ++ "` attribute, which it needs."
            , hint = Just ("Write it in the braces, such as `" ++ fence directive.kind ++ directive.name ++ "{" ++ name ++ "=\"…\"}`.")
            }

        Invalid invalid ->
            { title = "BAD ATTRIBUTE"
            , message =
                "The `"
                    ++ invalid.name
                    ++ "` attribute of `"
                    ++ directive.name
                    ++ "` should be "
                    ++ invalid.expected
                    ++ ", but it is "
                    ++ describeWritten invalid.written
                    ++ "."
            , hint = Nothing
            }

        Rejected message ->
            { title = "BAD ATTRIBUTE", message = message, hint = Nothing }


fence : Kind -> String
fence kind =
    case kind of
        Container ->
            ":::"

        Leaf ->
            "::"


{-| A bare `{open}` has the value `""`, which reads better as a word.
-}
describeWritten : String -> String
describeWritten written =
    if String.isEmpty written then
        "empty"

    else
        "`" ++ written ++ "`"



-- THE SITE


{-| A site's components whose names clash or cannot be written in Markdown.
-}
siteProblems : List Component -> List Diagnostic
siteProblems components =
    let
        names : List String
        names =
            List.map (\(Component component) -> component.name) components

        duplicates : List String
        duplicates =
            names
                |> List.filter (\name -> List.length (List.filter ((==) name) names) > 1)
                |> Results.unique
    in
    List.map badName (List.filter (not << isValidName) names)
        ++ List.map duplicate duplicates


{-| Markdown reads a directive's name as a letter, then letters, digits, `-`
and `_`; any other name could never be used.
-}
isValidName : String -> Bool
isValidName name =
    case String.uncons name of
        Just ( first, rest ) ->
            Char.isAlpha first && String.all (\char -> Char.isAlphaNum char || char == '-' || char == '_') rest

        Nothing ->
            False


badName : String -> Diagnostic
badName name =
    siteDiagnostic "BAD COMPONENT NAME"
        ("The site has a component named `" ++ name ++ "`, which Markdown cannot use as a name.")
        "A component's name starts with a letter, followed by letters, digits, `-` and `_`, such as `callout` or `video-embed`."


duplicate : String -> Diagnostic
duplicate name =
    siteDiagnostic "DUPLICATE COMPONENT"
        ("The site has more than one component named `" ++ name ++ "`.")
        "Markdown finds a component by its name, so each name can be used once."


siteDiagnostic : String -> String -> String -> Diagnostic
siteDiagnostic title message hint =
    { severity = Error
    , title = title
    , message = message
    , sourcePath = Nothing
    , span = Nothing
    , hint = Just hint
    }
