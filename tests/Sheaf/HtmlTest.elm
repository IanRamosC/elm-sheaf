module Sheaf.HtmlTest exposing (suite)

import Expect
import Fuzz
import Sheaf.Html as Html exposing (div, img, p, text)
import Sheaf.Html.Attributes as Attributes exposing (attribute, class, siteHref, siteSrc, src)
import Sheaf.Internal.Html exposing (HtmlProblem(..), problems, rewriteUrls, siteSrcset)
import Test exposing (Test, describe, fuzz, test)


suite : Test
suite =
    describe "Sheaf.Html"
        [ renderingTests
        , escapingTests
        , problemTests
        , rewriteTests
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
        , test "knows every HTML void element, such as source" <|
            \_ ->
                Html.toString (Html.node "source" [ src "a.webm" ] [])
                    |> Expect.equal "<source src=\"a.webm\">"
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
        , test "accepts a site path that starts with a single slash" <|
            \_ ->
                problems (Html.a [ siteHref "/archive/" ] [ img [ siteSrc "/cover.png" ] [] ])
                    |> Expect.equal []
        , test "reports a site path that does not start with a slash" <|
            \_ ->
                problems (Html.a [ siteHref "archive/" ] [])
                    |> Expect.equal [ InvalidSitePath { tag = "a", name = "href", path = "archive/" } ]
        , test "reports a site path that starts with two slashes, which a browser reads as another host" <|
            \_ ->
                problems (img [ siteSrc "//cdn.example.com/x" ] [])
                    |> Expect.equal [ InvalidSitePath { tag = "img", name = "src", path = "//cdn.example.com/x" } ]
        , test "reports a srcset path that is not a site path" <|
            \_ ->
                problems (img [ siteSrcset [ { path = "/a.png", width = 1 }, { path = "b.png", width = 2 } ] ] [])
                    |> Expect.equal [ InvalidSitePath { tag = "img", name = "srcset", path = "b.png" } ]
        , test "toString leaves out a site path that is not resolved" <|
            \_ ->
                Html.toString (Html.a [ siteHref "/archive/", class "a" ] [])
                    |> Expect.equal "<a class=\"a\"></a>"
        , test "toString leaves out an invalid attribute" <|
            \_ ->
                Html.toString (div [ attribute "on click" "x", class "a" ] [])
                    |> Expect.equal "<div class=\"a\"></div>"
        , test "toString leaves out an invalid or raw-text element" <|
            \_ ->
                Html.toString (div [] [ Html.node "my tag" [] [ text "x" ], Html.node "style" [] [ text "a > b" ], text "y" ])
                    |> Expect.equal "<div>y</div>"
        ]


rewriteTests : Test
rewriteTests =
    let
        rewritesSrcset : String -> String -> Test
        rewritesSrcset srcset rewritten =
            test ("`" ++ srcset ++ "`") <|
                \_ ->
                    img [ attribute "srcset" srcset ] []
                        |> rewriteUrls (\url -> "<" ++ url ++ ">")
                        |> Html.toString
                        |> Expect.equal ("<img srcset=\"" ++ rewritten ++ "\">")
    in
    describe "rewriteUrls"
        [ test "rewrites href and src, and leaves other attributes" <|
            \_ ->
                Html.a [ Attributes.href "a" ] [ img [ src "b", class "c" ] [] ]
                    |> rewriteUrls String.toUpper
                    |> Html.toString
                    |> Expect.equal "<a href=\"A\"><img src=\"B\" class=\"c\"></a>"
        , describe "rewrites each URL of a srcset"
            [ rewritesSrcset "a.png 480w, b.png 960w" "&lt;a.png&gt; 480w, &lt;b.png&gt; 960w"
            , rewritesSrcset "a.png 1x,b.png 2x" "&lt;a.png&gt; 1x, &lt;b.png&gt; 2x"
            , rewritesSrcset " a.png, b.png 2x " "&lt;a.png&gt;, &lt;b.png&gt; 2x"
            , rewritesSrcset "data:image/png;base64,AA 1x" "&lt;data:image/png;base64,AA&gt; 1x"
            ]
        ]


documentTests : Test
documentTests =
    describe "document"
        [ test "wraps head and body with doctype, language, UTF-8 charset and viewport" <|
            \_ ->
                Html.document
                    { lang = "en"
                    , head = [ Html.node "title" [] [ text "Hi" ] ]
                    , body = [ p [] [ text "x" ] ]
                    }
                    |> Expect.equal "<!DOCTYPE html><html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"><title>Hi</title></head><body><p>x</p></body></html>"
        ]
