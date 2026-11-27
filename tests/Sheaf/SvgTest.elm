module Sheaf.SvgTest exposing (suite)

import Expect
import Sheaf.Html as Html
import Sheaf.Internal.Html exposing (HtmlProblem(..), problems)
import Sheaf.Svg exposing (circle, linearGradient, node, path, stop, svg, title)
import Sheaf.Svg.Attributes exposing (d, fillRule, height, id, offset, stopColor, strokeWidth, viewBox, width)
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Sheaf.Svg"
        [ test "renders an icon with end tags and camelCase attributes" <|
            \_ ->
                Html.toString (svg [ viewBox "0 0 24 24", width "24", height "24" ] [ path [ d "M0 0h24", strokeWidth "2" ] [] ])
                    |> Expect.equal "<svg viewBox=\"0 0 24 24\" width=\"24\" height=\"24\"><path d=\"M0 0h24\" stroke-width=\"2\"></path></svg>"
        , test "keeps hyphenated SVG attribute names" <|
            \_ ->
                Html.toString (circle [ fillRule "evenodd", stopColor "red" ] [])
                    |> Expect.equal "<circle fill-rule=\"evenodd\" stop-color=\"red\"></circle>"
        , test "renders inside Sheaf.Html" <|
            \_ ->
                Html.toString (Html.span [] [ svg [] [ title [] [ Html.text "x & y" ] ] ])
                    |> Expect.equal "<span><svg><title>x &amp; y</title></svg></span>"
        , test "keeps a mixed-case element name" <|
            \_ ->
                Html.toString (linearGradient [ id "g" ] [ stop [ offset "0" ] [] ])
                    |> Expect.equal "<linearGradient id=\"g\"><stop offset=\"0\"></stop></linearGradient>"
        , test "refuses style inside svg" <|
            \_ ->
                problems (svg [] [ node "style" [] [] ])
                    |> Expect.equal [ RawTextElement "style" ]
        ]
