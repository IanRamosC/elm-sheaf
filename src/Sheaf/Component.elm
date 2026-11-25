module Sheaf.Component exposing
    ( Component, container, leaf
    , Attributes, succeed, required, optional, withDefault
    , Value, string, int, oneOf
    , map, validate
    )

{-| Components turn Markdown directives into views of your own.

A container component wraps Markdown between two fences, and its view gets the
rendered content:

```markdown
:::callout{kind="warning"}
Back up your files **first**.
:::
```

A leaf component stands on a line of its own, and its view gets only its
attributes:

```markdown
::youtube{id="dQw4w9WgXcQ"}
```

As with [`Sheaf.Frontmatter`](Sheaf-Frontmatter), the attributes are decoded
into a value of your own type. A component knows every attribute it takes, so a
misspelled `{knd="note"}` is reported with a suggestion instead of being
ignored, and every problem of a directive is reported at once, where it is
written.

    import Sheaf.Component as Component exposing (Component)
    import Sheaf.Html exposing (Html, aside, p, strong, text)
    import Sheaf.Html.Attributes exposing (class)

    type Kind
        = Note
        | Warning

    callout : Component
    callout =
        Component.container "callout"
            (Component.succeed identity
                |> Component.required "kind"
                    (Component.oneOf [ ( "note", Note ), ( "warning", Warning ) ])
            )
            calloutView

    calloutView : Kind -> List Html -> Html
    calloutView kind content =
        case kind of
            Note ->
                aside [ class "callout note" ] content

            Warning ->
                aside [ class "callout warning" ]
                    (p [] [ strong [] [ text "Warning" ] ] :: content)

A site lists its components in [`Sheaf.site`](Sheaf#site), or adds more with
[`Sheaf.withComponents`](Sheaf#withComponents). A directive that names no
component, or uses a leaf as a container, fails the build.

A name starts with a letter, followed by letters, digits, `-` and `_`, as
Markdown writes it, and each component of a site has its own.

In the braces, `#intro` is the attribute `id` and `.wide` is `class`, which a
component takes like any other, such as with
`Component.optional "class" Component.string`.

@docs Component, container, leaf


# Attributes

@docs Attributes, succeed, required, optional, withDefault


# Values

@docs Value, string, int, oneOf


# Transforming values

@docs map, validate

-}

import Sheaf.Html exposing (Html)
import Sheaf.Internal.Component as Internal


{-| A name, the attributes it takes and how it looks.
-}
type alias Component =
    Internal.Component


{-| A component that wraps Markdown, written as `:::name{…}` and closed with
`:::`. Its view gets the decoded attributes and the rendered content.

    Component.container "aside"
        (Component.succeed ())
        (\() content -> aside [] content)

-}
container : String -> Attributes a -> (a -> List Html -> Html) -> Component
container =
    Internal.container


{-| A component on a line of its own, written as `::name{…}`. Its view gets
the decoded attributes.

    Component.leaf "youtube"
        (Component.succeed identity |> Component.required "id" Component.string)
        (\id -> div [ class "video", attribute "data-id" id ] [])

-}
leaf : String -> Attributes a -> (a -> Html) -> Component
leaf =
    Internal.leaf


{-| A decoder for the attributes of a component.
-}
type alias Attributes a =
    Internal.Attributes a


{-| Start a record, given the function that builds it from its attributes.

    type alias Figure =
        { src : String, caption : Maybe String }

    figureAttributes : Attributes Figure
    figureAttributes =
        Component.succeed Figure
            |> Component.required "src" Component.string
            |> Component.optional "caption" Component.string

A component that takes no attributes starts from `Component.succeed ()`.

-}
succeed : a -> Attributes a
succeed =
    Internal.succeed


{-| Add an attribute that must be written.

    Component.succeed identity
        |> Component.required "id" Component.string

-}
required : String -> Value a -> Attributes (a -> b) -> Attributes b
required =
    Internal.required


{-| Add an attribute that may be left out.

    Component.succeed identity
        |> Component.optional "caption" Component.string

-}
optional : String -> Value a -> Attributes (Maybe a -> b) -> Attributes b
optional =
    Internal.optional


{-| Add an attribute that falls back to a default when it is left out.

    Component.succeed identity
        |> Component.withDefault "width" 560 Component.int

-}
withDefault : String -> a -> Value a -> Attributes (a -> b) -> Attributes b
withDefault =
    Internal.withDefault


{-| How to decode the text of one attribute.
-}
type alias Value a =
    Internal.Value a


{-| The text as written, which may be empty: `{open}` is the text `""`.

    Component.required "title" Component.string

-}
string : Value String
string =
    Internal.string


{-| A whole number, such as `{width=640}`.

    Component.withDefault "width" 560 Component.int

-}
int : Value Int
int =
    Internal.int


{-| One of a fixed set of texts, each standing for a value.

    Component.oneOf
        [ ( "note", Note )
        , ( "warning", Warning )
        ]

Any other text is reported along with the allowed ones.

-}
oneOf : List ( String, a ) -> Value a
oneOf =
    Internal.oneOf


{-| Transform a decoded value.

    Component.string
        |> Component.map String.toUpper

-}
map : (a -> b) -> Value a -> Value b
map =
    Internal.map


{-| Check or convert a decoded value. The message of an `Err` becomes the
message of the diagnostic as it is, so write it as a sentence.

    Component.int
        |> Component.validate
            (\width ->
                if width > 0 then
                    Ok width

                else
                    Err "The `width` of a video must be more than 0."
            )

-}
validate : (a -> Result String b) -> Value a -> Value b
validate =
    Internal.validate
