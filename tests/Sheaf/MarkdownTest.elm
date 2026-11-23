module Sheaf.MarkdownTest exposing (suite)

import Expect
import Json.Decode as Decode
import ProtocolFixtures
import Sheaf.Html as Html
import Sheaf.Internal.Markdown as Internal
import Sheaf.Internal.Protocol as Protocol exposing (Alignment(..), Node(..))
import Sheaf.Markdown as Markdown
import Sheaf.Ref as Ref exposing (Ref)
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Sheaf.Markdown"
        [ blockTests
        , inlineTests
        , listTests
        , tableTests
        , footnoteTests
        , linkTests
        , fixtureTests
        ]



-- BUILDING TREES


at : Int -> Protocol.Span
at line =
    { start = { line = line, column = 1 }, end = { line = line, column = 10 } }


text : String -> Node
text value =
    Text { position = at 1, value = value }


paragraph : List Node -> Node
paragraph children =
    Paragraph { position = at 1, children = children }


root : List Node -> Node
root children =
    Root { position = at 1, children = children }


sheafLink : { collection : String, slug : String, fragment : Maybe String } -> Node
sheafLink target =
    SheafLink
        { position = at 3
        , collection = target.collection
        , slug = target.slug
        , fragment = target.fragment
        , title = Nothing
        , children = [ text "link" ]
        }


noLinks : Ref -> Maybe String
noLinks _ =
    Nothing


helloWorldAt : String -> Ref -> Maybe String
helloWorldAt url ref =
    if Ref.id ref == "posts/hello-world" then
        Just url

    else
        Nothing



-- RENDERING


renderWith : (Ref -> Maybe String) -> Node -> Result (List Markdown.LinkProblem) String
renderWith resolve node =
    Internal.fromNode node
        |> Markdown.render resolve
        |> Result.map (List.map Html.toString >> String.concat)


rendersTo : String -> Node -> Expect.Expectation
rendersTo expected node =
    renderWith noLinks (root [ node ])
        |> Expect.equal (Ok expected)


blockTests : Test
blockTests =
    describe "blocks"
        [ test "a paragraph" <|
            \_ ->
                paragraph [ text "a < b" ]
                    |> rendersTo "<p>a &lt; b</p>"
        , test "a heading gets its id and level" <|
            \_ ->
                Heading { position = at 1, depth = 3, id = "setup", children = [ text "Setup" ] }
                    |> rendersTo "<h3 id=\"setup\">Setup</h3>"
        , test "a code block with a language" <|
            \_ ->
                Code { position = at 1, lang = Just "elm", value = "x = 1" }
                    |> rendersTo "<pre><code class=\"language-elm\">x = 1\n</code></pre>"
        , test "a code block without a language" <|
            \_ ->
                Code { position = at 1, lang = Nothing, value = "x" }
                    |> rendersTo "<pre><code>x\n</code></pre>"
        , test "a block quote" <|
            \_ ->
                Blockquote { position = at 1, children = [ paragraph [ text "q" ] ] }
                    |> rendersTo "<blockquote><p>q</p></blockquote>"
        , test "a thematic break" <|
            \_ ->
                ThematicBreak { position = at 1 }
                    |> rendersTo "<hr>"
        ]


inlineTests : Test
inlineTests =
    describe "inline content"
        [ test "emphasis, strong and deletion" <|
            \_ ->
                paragraph
                    [ Emphasis { position = at 1, children = [ text "a" ] }
                    , Strong { position = at 1, children = [ text "b" ] }
                    , Delete { position = at 1, children = [ text "c" ] }
                    ]
                    |> rendersTo "<p><em>a</em><strong>b</strong><del>c</del></p>"
        , test "inline code is escaped" <|
            \_ ->
                paragraph [ InlineCode { position = at 1, value = "x < y" } ]
                    |> rendersTo "<p><code>x &lt; y</code></p>"
        , test "a hard break" <|
            \_ ->
                paragraph [ text "a", Break { position = at 1 }, text "b" ]
                    |> rendersTo "<p>a<br>b</p>"
        , test "an external link keeps its title" <|
            \_ ->
                paragraph [ Link { position = at 1, url = "https://example.com", title = Just "Ex", children = [ text "e" ] } ]
                    |> rendersTo "<p><a href=\"https://example.com\" title=\"Ex\">e</a></p>"
        , test "an image" <|
            \_ ->
                paragraph [ Image { position = at 1, url = "a.png", alt = "A cat", title = Nothing } ]
                    |> rendersTo "<p><img src=\"a.png\" alt=\"A cat\"></p>"
        ]


listNode : { ordered : Bool, start : Maybe Int, spread : Bool } -> List Node -> Node
listNode list items =
    ListBlock
        { position = at 1
        , ordered = list.ordered
        , start = list.start
        , spread = list.spread
        , children = items
        }


item : Maybe Bool -> String -> Node
item checked content =
    ListItem { position = at 1, checked = checked, children = [ paragraph [ text content ] ] }


listTests : Test
listTests =
    describe "lists"
        [ test "a tight bullet list has no paragraphs" <|
            \_ ->
                listNode { ordered = False, start = Nothing, spread = False } [ item Nothing "a", item Nothing "b" ]
                    |> rendersTo "<ul><li>a</li><li>b</li></ul>"
        , test "a spread list keeps its paragraphs" <|
            \_ ->
                listNode { ordered = False, start = Nothing, spread = True } [ item Nothing "a" ]
                    |> rendersTo "<ul><li><p>a</p></li></ul>"
        , test "an ordered list starting elsewhere than 1" <|
            \_ ->
                listNode { ordered = True, start = Just 3, spread = False } [ item Nothing "a" ]
                    |> rendersTo "<ol start=\"3\"><li>a</li></ol>"
        , test "an ordered list starting at 1 needs no attribute" <|
            \_ ->
                listNode { ordered = True, start = Just 1, spread = False } [ item Nothing "a" ]
                    |> rendersTo "<ol><li>a</li></ol>"
        , test "task items render a disabled checkbox" <|
            \_ ->
                listNode { ordered = False, start = Nothing, spread = False } [ item (Just True) "done", item (Just False) "todo" ]
                    |> rendersTo "<ul><li class=\"task-list-item\"><input type=\"checkbox\" checked disabled> done</li><li class=\"task-list-item\"><input type=\"checkbox\" disabled> todo</li></ul>"
        ]


cell : String -> Node
cell content =
    TableCell { position = at 1, children = [ text content ] }


row : List String -> Node
row cells =
    TableRow { position = at 1, children = List.map cell cells }


tableTests : Test
tableTests =
    describe "tables"
        [ test "the first row is the head and the rest the body" <|
            \_ ->
                Table { position = at 1, align = [ Nothing, Nothing ], children = [ row [ "a", "b" ], row [ "1", "2" ], row [ "3", "4" ] ] }
                    |> rendersTo "<table><thead><tr><th>a</th><th>b</th></tr></thead><tbody><tr><td>1</td><td>2</td></tr><tr><td>3</td><td>4</td></tr></tbody></table>"
        , test "a table with only a head has no body" <|
            \_ ->
                Table { position = at 1, align = [ Nothing ], children = [ row [ "a" ] ] }
                    |> rendersTo "<table><thead><tr><th>a</th></tr></thead></table>"
        , test "column alignment becomes a style on every cell of the column" <|
            \_ ->
                Table { position = at 1, align = [ Just AlignLeft, Just AlignCenter, Just AlignRight, Nothing ], children = [ row [ "a", "b", "c", "d" ], row [ "1", "2", "3", "4" ] ] }
                    |> rendersTo "<table><thead><tr><th style=\"text-align: left\">a</th><th style=\"text-align: center\">b</th><th style=\"text-align: right\">c</th><th>d</th></tr></thead><tbody><tr><td style=\"text-align: left\">1</td><td style=\"text-align: center\">2</td><td style=\"text-align: right\">3</td><td>4</td></tr></tbody></table>"
        ]


reference : String -> Node
reference =
    referenceOnLine 1


referenceOnLine : Int -> String -> Node
referenceOnLine line identifier =
    FootnoteReference { position = at line, identifier = identifier }


definition : String -> String -> Node
definition identifier content =
    FootnoteDefinition { position = at 9, identifier = identifier, children = [ paragraph [ text content ] ] }


backLink : String -> Int -> String
backLink id number =
    " <a href=\"#user-content-fnref-" ++ id ++ "\" data-footnote-backref aria-label=\"Back to reference " ++ String.fromInt number ++ "\">↩</a>"


footnoteTests : Test
footnoteTests =
    describe "footnotes"
        [ test "a reference links to its definition and the definitions close the body" <|
            \_ ->
                renderWith noLinks (root [ paragraph [ text "a", reference "x" ], definition "x" "Note." ])
                    |> Expect.equal
                        (Ok
                            ("<p>a<sup><a href=\"#user-content-fn-x\" id=\"user-content-fnref-x\" data-footnote-ref>1</a></sup></p>"
                                ++ "<section data-footnotes class=\"footnotes\"><ol><li id=\"user-content-fn-x\"><p>Note."
                                ++ backLink "x" 1
                                ++ "</p></li></ol></section>"
                            )
                        )
        , test "footnotes are numbered by first reference, not by definition order" <|
            \_ ->
                renderWith noLinks (root [ paragraph [ reference "b", reference "a" ], definition "a" "A", definition "b" "B" ])
                    |> Result.map (String.contains "<li id=\"user-content-fn-b\"><p>B")
                    |> Expect.equal (Ok True)
        , test "a second reference to the same footnote has the same number and no duplicate id" <|
            \_ ->
                renderWith noLinks (root [ paragraph [ reference "x", referenceOnLine 2 "x" ], definition "x" "Note." ])
                    |> Result.map (String.split "id=\"user-content-fnref-x\"" >> List.length)
                    |> Expect.equal (Ok 2)
        , test "identifiers are lower-cased" <|
            \_ ->
                renderWith noLinks (root [ paragraph [ reference "Note" ], definition "Note" "N" ])
                    |> Result.map (String.contains "id=\"user-content-fn-note\"")
                    |> Expect.equal (Ok True)
        , test "a reference without a definition stays as text" <|
            \_ ->
                renderWith noLinks (root [ paragraph [ reference "lost" ] ])
                    |> Expect.equal (Ok "<p>[^lost]</p>")
        , test "a definition nobody references is not rendered" <|
            \_ ->
                renderWith noLinks (root [ paragraph [ text "a" ], definition "x" "Note." ])
                    |> Expect.equal (Ok "<p>a</p>")
        ]


linkTests : Test
linkTests =
    describe "links between documents"
        [ test "a resolved link keeps its fragment" <|
            \_ ->
                renderWith (helloWorldAt "/blog/posts/hello-world/")
                    (root [ paragraph [ sheafLink { collection = "posts", slug = "hello-world", fragment = Just "setup" } ] ])
                    |> Expect.equal (Ok "<p><a href=\"/blog/posts/hello-world/#setup\">link</a></p>")
        , test "a resolved link without a fragment" <|
            \_ ->
                renderWith (helloWorldAt "/blog/posts/hello-world/")
                    (root [ paragraph [ sheafLink { collection = "posts", slug = "hello-world", fragment = Nothing } ] ])
                    |> Expect.equal (Ok "<p><a href=\"/blog/posts/hello-world/\">link</a></p>")
        , test "an unresolvable link is an error carrying its span and target" <|
            \_ ->
                renderWith noLinks
                    (root [ paragraph [ sheafLink { collection = "posts", slug = "gone", fragment = Nothing } ] ])
                    |> Expect.equal (Err [ { span = at 3, id = "posts/gone" } ])
        , test "every unresolvable link is reported" <|
            \_ ->
                renderWith noLinks
                    (root
                        [ paragraph [ sheafLink { collection = "posts", slug = "one", fragment = Nothing } ]
                        , Blockquote { position = at 1, children = [ paragraph [ sheafLink { collection = "posts", slug = "two", fragment = Nothing } ] ] }
                        ]
                    )
                    |> Result.mapError (List.map .id)
                    |> Expect.equal (Err [ "posts/one", "posts/two" ])
        ]


fixtureTests : Test
fixtureTests =
    describe "a decoded request"
        [ test "every node type renders" <|
            \_ ->
                Decode.decodeString Protocol.requestDecoder ProtocolFixtures.allNodesRequest
                    |> Result.map (.documents >> List.map .tree)
                    |> Result.map (List.map (renderWith (helloWorldAt "/blog/posts/hello-world/")))
                    |> Expect.equal (Ok [ Ok allNodesHtml ])
        ]


allNodesHtml : String
allNodesHtml =
    String.concat
        [ "<h2 id=\"intro\">Intro</h2>"
        , "<p>Plain <em>em</em><strong>strong</strong><del>del</del><code>x &lt; y</code><br>"
        , "<a href=\"https://example.com\" title=\"Example\">ext</a>"
        , "<a href=\"/blog/posts/hello-world/#setup\">setup</a>"
        , "<img src=\"a.png\" alt=\"A cat\" title=\"Cat\">"
        , "<sup><a href=\"#user-content-fn-note\" id=\"user-content-fnref-note\" data-footnote-ref>1</a></sup></p>"
        , "<pre><code class=\"language-elm\">x = 1\n</code></pre>"
        , "<pre><code>plain\n</code></pre>"
        , "<blockquote><p>quoted</p></blockquote>"
        , "<ol start=\"3\"><li class=\"task-list-item\"><input type=\"checkbox\" checked disabled> done</li>"
        , "<li class=\"task-list-item\"><input type=\"checkbox\" disabled> todo</li><li>plain</li></ol>"
        , "<ul><li><p>loose</p></li></ul>"
        , "<hr>"
        , "<table><thead><tr><th style=\"text-align: left\">A</th><th style=\"text-align: center\">B</th>"
        , "<th style=\"text-align: right\">C</th><th>D</th></tr></thead>"
        , "<tbody><tr><td style=\"text-align: left\">1</td><td style=\"text-align: center\">2</td>"
        , "<td style=\"text-align: right\">3</td><td>4</td></tr></tbody></table>"
        , "<section data-footnotes class=\"footnotes\"><ol><li id=\"user-content-fn-note\"><p>The note."
        , backLink "note" 1
        , "</p></li></ol></section>"
        ]
