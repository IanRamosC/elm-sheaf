module Theme.Components exposing (callout)

{-| Components that posts and pages use as Markdown directives.
-}

import Sheaf.Component as Component exposing (Component)
import Sheaf.Html exposing (Html, aside, p, strong, text)
import Sheaf.Html.Attributes exposing (class)


type CalloutKind
    = Note
    | Warning


{-| A box set apart from the text around it:

    :::callout{kind=note}
    Drafts are left out of `sheaf build`.
    :::

`kind` is `note` or `warning`.

-}
callout : Component
callout =
    Component.container "callout"
        (Component.succeed identity
            |> Component.required "kind"
                (Component.oneOf [ ( "note", Note ), ( "warning", Warning ) ])
        )
        calloutView


calloutView : CalloutKind -> List Html -> Html
calloutView kind content =
    let
        ( name, label ) =
            case kind of
                Note ->
                    ( "note", "Note" )

                Warning ->
                    ( "warning", "Warning" )
    in
    -- The label is written out, so the kind doesn't rest on colour alone.
    aside [ class ("callout " ++ name) ]
        (p [ class "callout-label" ] [ strong [] [ text label ] ] :: content)
