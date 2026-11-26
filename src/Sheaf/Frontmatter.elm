module Sheaf.Frontmatter exposing
    ( Frontmatter, Field
    , succeed, required, optional, withDefault
    , string, int, float, bool, list, oneOf
    , map, validate, fromDecoder
    )

{-| Declare the frontmatter of a collection.

Unlike a plain `Json.Decode` decoder, a `Frontmatter` knows every field name it
expects. A misspelled key such as `sumary:` is reported with a suggestion
instead of being silently ignored, and every problem in a file is reported at
once, at the line and column where it is.

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

The keys `slug`, `date`, `updated`, `draft`, `image` and `aliases` are read by
Sheaf itself and never reach a `Frontmatter`. Templates get the slug, the
dates and the image from the `Document`, but not `aliases`, the old paths that
Sheaf redirects to the document.

@docs Frontmatter, Field


# Records

@docs succeed, required, optional, withDefault


# Fields

@docs string, int, float, bool, list, oneOf


# Transforming fields

@docs map, validate, fromDecoder

-}

import Json.Decode exposing (Decoder)
import Sheaf.Internal.Frontmatter as Internal


{-| A decoder for the frontmatter of one collection.
-}
type alias Frontmatter a =
    Internal.Frontmatter a


{-| How to decode the value of one key.
-}
type alias Field a =
    Internal.Field a


{-| Start a record, given the function that builds it from its fields.
-}
succeed : a -> Frontmatter a
succeed =
    Internal.succeed


{-| Add a field that must be present.

A key with no value counts as present but empty, which is not a valid value for
any field, so it is reported.

-}
required : String -> Field a -> Frontmatter (a -> b) -> Frontmatter b
required =
    Internal.required


{-| Add a field that may be left out, or written with no value.
-}
optional : String -> Field a -> Frontmatter (Maybe a -> b) -> Frontmatter b
optional =
    Internal.optional


{-| Add a field that falls back to a default when it is left out or has no
value.
-}
withDefault : String -> a -> Field a -> Frontmatter (a -> b) -> Frontmatter b
withDefault =
    Internal.withDefault


{-| Text.
-}
string : Field String
string =
    Internal.string


{-| A whole number.
-}
int : Field Int
int =
    Internal.int


{-| A number, with or without decimals.
-}
float : Field Float
float =
    Internal.float


{-| `true` or `false`.
-}
bool : Field Bool
bool =
    Internal.bool


{-| A list. Every item that does not decode is reported.
-}
list : Field a -> Field (List a)
list =
    Internal.list


{-| One of a fixed set of strings, each standing for a value.

    Frontmatter.oneOf
        [ ( "draft", Draft )
        , ( "published", Published )
        ]

Any other value is reported along with the allowed ones.

-}
oneOf : List ( String, a ) -> Field a
oneOf =
    Internal.oneOf


{-| Transform a decoded value.
-}
map : (a -> b) -> Field a -> Field b
map =
    Internal.map


{-| Check or convert a decoded value. The message of an `Err` becomes the
message of the diagnostic as it is, so write it as a sentence.

    Frontmatter.string
        |> Frontmatter.validate
            (\title ->
                if String.length title > 70 then
                    Err "The `title` is longer than 70 characters."

                else
                    Ok title
            )

-}
validate : (a -> Result String b) -> Field a -> Field b
validate =
    Internal.validate


{-| Decode a value, such as a nested object, with a `Json.Decode` decoder.

The keys inside the value are not checked: a misspelled key in a nested object
is ignored, as it is with any decoder.

-}
fromDecoder : Decoder a -> Field a
fromDecoder =
    Internal.fromDecoder
