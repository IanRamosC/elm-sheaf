module Sheaf.HtmlTest exposing (suite)

import Expect
import Fuzz
import Sheaf.Html as Html exposing (div, img, p, text)
import Sheaf.Html.Attributes as Attributes exposing (attribute, class, src)
import Sheaf.Internal.Html exposing (HtmlProblem(..), problems)
import Test exposing (Test, describe, fuzz, test)


suite : Test
suite =
    describe "Sheaf.Html"
        [ renderingTests
        , escapingTests
        , problemTests
        , documentTests
        ]


renderingTests : Test
renderingTests =
    describe "toString"
        [ test "renders an element with an attribute and escaped text" <|
            \_ ->
                Html.toString (p [ class "a" ] [ text "x < y & z" ])
                    |> Expect.equal "<p class=\"a\">x &lt; y &amp; z</p>"
        , test "renders void elements without a closing tag or children" <|
            \_ ->
                Html.toString (img [ src "a.png" ] [ text "ignored" ])
                    |> Expect.equal "<img src=\"a.png\">"
        , test "renders nested children in order" <|
            \_ ->
                Html.toString (div [] [ p [] [ text "a" ], p [] [ text "b" ] ])
                    |> Expect.equal "<div><p>a</p><p>b</p></div>"
        , test "renders a true boolean attribute bare and omits a false one" <|
            \_ ->
                Html.toString (Html.input [ Attributes.checked True, Attributes.disabled False ] [])
                    |> Expect.equal "<input checked>"
        , test "renders an integer attribute" <|
            \_ ->
                Html.toString (img [ Attributes.width 16 ] [])
                    |> Expect.equal "<img width=\"16\">"
        ]


escapingTests : Test
escapingTests =
    describe "escaping"
        [ test "escapes quotes and ampersands in attribute values" <|
            \_ ->
                Html.toString (div [ attribute "data-x" "He said \"hi\" & 'bye'" ] [])
                    |> Expect.equal "<div data-x=\"He said &quot;hi&quot; &amp; &#39;bye&#39;\"></div>"
        , fuzz Fuzz.string "text never produces angle brackets" <|
            \s ->
                Html.toString (text s)
                    |> Expect.all
                        [ \out -> Expect.equal False (String.contains "<" out)
                        , \out -> Expect.equal False (String.contains ">" out)
                        ]
        , fuzz Fuzz.string "an attribute value never adds quotes" <|
            \s ->
                Html.toString (div [ attribute "data-x" s ] [])
                    |> String.filter ((==) '"')
                    |> String.length
                    |> Expect.equal 2
        ]


problemTests : Test
problemTests =
    describe "problems"
        [ test "reports nothing for a valid tree" <|
            \_ ->
                problems (div [ class "a" ] [ p [] [ text "x" ], Html.node "my-element" [] [] ])
                    |> Expect.equal []
        , test "reports an invalid attribute name once" <|
            \_ ->
                problems (div [ attribute "on click" "x" ] [])
                    |> Expect.equal [ InvalidAttributeName { tag = "div", name = "on click" } ]
        , test "reports an invalid tag name once" <|
            \_ ->
                problems (Html.node "my tag" [] [])
                    |> Expect.equal [ InvalidTagName "my tag" ]
        , test "reports style and script built with node" <|
            \_ ->
                problems (div [] [ Html.node "style" [] [], Html.node "Script" [] [] ])
                    |> Expect.equal [ RawTextElement "style", RawTextElement "Script" ]
        , test "finds problems in nested children" <|
            \_ ->
                problems (div [] [ p [] [ Html.node "1x" [] [] ] ])
                    |> Expect.equal [ InvalidTagName "1x" ]
        , test "toString leaves out an invalid attribute" <|
            \_ ->
                Html.toString (div [ attribute "on click" "x", class "a" ] [])
                    |> Expect.equal "<div class=\"a\"></div>"
        , test "toString leaves out an invalid or raw-text element" <|
            \_ ->
                Html.toString (div [] [ Html.node "my tag" [] [ text "x" ], Html.node "style" [] [ text "a > b" ], text "y" ])
                    |> Expect.equal "<div>y</div>"
        ]


documentTests : Test
documentTests =
    describe "document"
        [ test "wraps head and body with doctype, language and UTF-8 charset" <|
            \_ ->
                Html.document
                    { lang = "en"
                    , head = [ Html.node "title" [] [ text "Hi" ] ]
                    , body = [ p [] [ text "x" ] ]
                    }
                    |> Expect.equal "<!DOCTYPE html><html lang=\"en\"><head><meta charset=\"utf-8\"><title>Hi</title></head><body><p>x</p></body></html>"
        ]
