module Sheaf.MarkdownTest exposing (suite)

import Dict
import Expect
import Json.Decode as Decode
import ProtocolFixtures
import Sheaf.Component as Component exposing (Component)
import Sheaf.Html as Html
import Sheaf.Html.Attributes as Attributes
import Sheaf.Internal.Component as Internal
import Sheaf.Internal.Html as InternalHtml exposing (Url(..))
import Sheaf.Internal.Markdown as Markdown exposing (Problem(..))
import Sheaf.Internal.Protocol as Protocol exposing (Alignment(..), Node(..))
import Sheaf.Ref as Ref exposing (Ref)
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Sheaf.Internal.Markdown"
        [ blockTests
        , headingTests
        , inlineTests
        , listTests
        , tableTests
        , footnoteTests
        , linkTests
        , directiveTests
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


renderWith : (Ref -> Maybe String) -> Node -> Result (List Problem) String
renderWith resolve node =
    Markdown.fromNode node
        |> Markdown.render { resolve = resolve, components = Dict.empty }
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
                    |> rendersTo "<h3 id=\"setup\">Setup <a class=\"heading-link\" href=\"#setup\" aria-labelledby=\"setup\">#</a></h3>"
        , test "a highlighted code block keeps its text exactly, escaped" <|
            \_ ->
                Code
                    { position = at 1
                    , lang = Just "elm"
                    , value = "a < b && \"c\"\n\tx\n"
                    , highlight =
                        { style = blockStyle
                        , lines =
                            [ [ { content = "a", style = "color:#24292E" }, { content = " < b && \"c\"", style = "" } ]
                            , [ { content = "\tx", style = "color:#D73A49;--shiki-dark:#F97583" } ]
                            , []
                            ]
                        }
                    }
                    |> rendersTo
                        (String.concat
                            [ "<pre class=\"shiki\" style=\"" ++ blockStyle ++ "\" tabindex=\"0\"><code class=\"language-elm\">"
                            , "<span class=\"line\"><span style=\"color:#24292E\">a</span><span> &lt; b &amp;&amp; &quot;c&quot;</span></span>\n"
                            , "<span class=\"line\"><span style=\"color:#D73A49;--shiki-dark:#F97583\">\tx</span></span>\n"
                            , "<span class=\"line\"></span>"
                            , "</code></pre>"
                            ]
                        )
        , test "an empty code block has no lines" <|
            \_ ->
                Code { position = at 1, lang = Just "elm", value = "", highlight = { style = blockStyle, lines = [] } }
                    |> rendersTo ("<pre class=\"shiki\" style=\"" ++ blockStyle ++ "\" tabindex=\"0\"><code class=\"language-elm\"></code></pre>")
        , test "a code block without a language has no language class" <|
            \_ ->
                Code { position = at 1, lang = Nothing, value = "x", highlight = { style = blockStyle, lines = [ [ { content = "x", style = "" } ] ] } }
                    |> rendersTo ("<pre class=\"shiki\" style=\"" ++ blockStyle ++ "\" tabindex=\"0\"><code><span class=\"line\"><span>x</span></span></code></pre>")
        , test "a block quote" <|
            \_ ->
                Blockquote { position = at 1, children = [ paragraph [ text "q" ] ] }
                    |> rendersTo "<blockquote><p>q</p></blockquote>"
        , test "a thematic break" <|
            \_ ->
                ThematicBreak { position = at 1 }
                    |> rendersTo "<hr>"
        ]


blockStyle : String
blockStyle =
    "background-color:#fff;--shiki-dark-bg:#24292e;color:#24292e;--shiki-dark:#e1e4e8"


headingTests : Test
headingTests =
    let
        heading : Int -> String -> List Node -> Node
        heading depth id children =
            Heading { position = at 1, depth = depth, id = id, children = children }
    in
    describe "headings"
        [ test "headings lists every heading in order" <|
            \_ ->
                -- # A\n## B\n### C\n## D
                root [ heading 1 "a" [ text "A" ], heading 2 "b" [ text "B" ], heading 3 "c" [ text "C" ], heading 2 "d" [ text "D" ] ]
                    |> Markdown.headings
                    |> Expect.equal
                        [ { depth = 1, id = "a", text = "A" }
                        , { depth = 2, id = "b", text = "B" }
                        , { depth = 3, id = "c", text = "C" }
                        , { depth = 2, id = "d", text = "D" }
                        ]
        , test "heading text drops markup" <|
            \_ ->
                -- ## Use `elm make` with [docs](https://x.y) and *care*[^1]
                root
                    [ heading 2
                        "use-elm-make-with-docs-and-care"
                        [ text "Use "
                        , InlineCode { position = at 1, value = "elm make" }
                        , text " with "
                        , Link { position = at 1, url = "https://x.y", title = Nothing, children = [ text "docs" ] }
                        , text " and "
                        , Emphasis { position = at 1, children = [ text "care" ] }
                        , FootnoteReference { position = at 1, identifier = "1" }
                        ]
                    ]
                    |> Markdown.headings
                    |> List.map .text
                    |> Expect.equal [ "Use elm make with docs and care" ]
        , test "heading text leaves images out" <|
            \_ ->
                root [ heading 2 "a-cat" [ text "A cat ", Image { position = at 1, url = "cat.png", alt = "Cat", title = Nothing, local = Nothing } ] ]
                    |> Markdown.headings
                    |> List.map .text
                    |> Expect.equal [ "A cat " ]
        , test "headings inside containers count" <|
            \_ ->
                root
                    [ ContainerDirective { position = at 1, name = "callout", attributes = [], children = [ heading 2 "in-a-callout" [ text "In a callout" ] ] }
                    , Blockquote { position = at 1, children = [ heading 2 "in-a-quote" [ text "In a quote" ] ] }
                    , ListBlock
                        { position = at 1
                        , ordered = False
                        , start = Nothing
                        , spread = False
                        , children = [ ListItem { position = at 1, checked = Nothing, children = [ heading 3 "in-a-list" [ text "In a list" ] ] } ]
                        }
                    ]
                    |> Markdown.headings
                    |> List.map .id
                    |> Expect.equal [ "in-a-callout", "in-a-quote", "in-a-list" ]
        , test "a heading without an id has no self-link" <|
            \_ ->
                heading 2 "" [ text "!!!" ]
                    |> renderWith noLinks
                    |> Result.map (String.contains "heading-link")
                    |> Expect.equal (Ok False)
        , test "a heading links to itself" <|
            \_ ->
                heading 2 "setup" [ text "Setup" ]
                    |> rendersTo "<h2 id=\"setup\">Setup <a class=\"heading-link\" href=\"#setup\" aria-labelledby=\"setup\">#</a></h2>"
        , test "the self-link sits outside a link in the heading" <|
            \_ ->
                heading 2 "docs" [ Link { position = at 1, url = "https://x.y", title = Nothing, children = [ text "Docs" ] } ]
                    |> rendersTo "<h2 id=\"docs\"><a href=\"https://x.y\">Docs</a> <a class=\"heading-link\" href=\"#docs\" aria-labelledby=\"docs\">#</a></h2>"
        , test "a heading's self-link can be taken out, leaving its own link" <|
            \_ ->
                Markdown.fromNode (root [ heading 2 "docs" [ Link { position = at 1, url = "https://x.y", title = Nothing, children = [ text "Docs" ] } ] ])
                    |> Markdown.render { resolve = noLinks, components = Dict.empty }
                    |> Result.map (List.map (InternalHtml.withoutHeadingLinks >> Html.toString) >> String.concat)
                    |> Expect.equal (Ok "<h2 id=\"docs\"><a href=\"https://x.y\">Docs</a></h2>")
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
                paragraph [ Image { position = at 1, url = "a.png", alt = "A cat", title = Nothing, local = Nothing } ]
                    |> rendersTo "<p><img src=\"a.png\" alt=\"A cat\" loading=\"lazy\" decoding=\"async\"></p>"
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
        , test "a loose task item has its checkbox inside the first paragraph" <|
            \_ ->
                listNode { ordered = False, start = Nothing, spread = True } [ item (Just False) "Write it" ]
                    |> rendersTo "<ul><li class=\"task-list-item\"><p><input type=\"checkbox\" disabled> Write it</p></li></ul>"
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
    definitionOf identifier [ text content ]


definitionOf : String -> List Node -> Node
definitionOf identifier content =
    FootnoteDefinition { position = at 9, identifier = identifier, children = [ paragraph content ] }


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
        , test "a second reference to the same footnote has the same number, its own id and its own back link" <|
            \_ ->
                renderWith noLinks (root [ paragraph [ reference "a", referenceOnLine 2 "a" ], definition "a" "Note." ])
                    |> Expect.equal
                        (Ok
                            ("<p><sup><a href=\"#user-content-fn-a\" id=\"user-content-fnref-a\" data-footnote-ref>1</a></sup>"
                                ++ "<sup><a href=\"#user-content-fn-a\" id=\"user-content-fnref-a-2\" data-footnote-ref>1</a></sup></p>"
                                ++ "<section data-footnotes class=\"footnotes\"><ol><li id=\"user-content-fn-a\"><p>Note."
                                ++ backLink "a" 1
                                ++ " <a href=\"#user-content-fnref-a-2\" data-footnote-backref aria-label=\"Back to reference 1-2\">↩<sup>2</sup></a>"
                                ++ "</p></li></ol></section>"
                            )
                        )
        , test "references inside a definition nobody references are not counted" <|
            \_ ->
                renderWith noLinks (root [ paragraph [ text "a" ], definitionOf "b" [ text "B", referenceOnLine 9 "c" ], definition "c" "C" ])
                    |> Expect.equal (Ok "<p>a</p>")
        , test "a footnote referenced only from a rendered definition is numbered after the body's, wherever the definitions are" <|
            \_ ->
                renderWith noLinks
                    (root
                        [ definitionOf "a" [ text "A", referenceOnLine 9 "c" ]
                        , definition "b" "B"
                        , definition "c" "C"
                        , paragraph [ reference "a", referenceOnLine 2 "b" ]
                        ]
                    )
                    |> Expect.equal
                        (Ok
                            ("<p><sup><a href=\"#user-content-fn-a\" id=\"user-content-fnref-a\" data-footnote-ref>1</a></sup>"
                                ++ "<sup><a href=\"#user-content-fn-b\" id=\"user-content-fnref-b\" data-footnote-ref>2</a></sup></p>"
                                ++ "<section data-footnotes class=\"footnotes\"><ol>"
                                ++ "<li id=\"user-content-fn-a\"><p>A<sup><a href=\"#user-content-fn-c\" id=\"user-content-fnref-c\" data-footnote-ref>3</a></sup>"
                                ++ backLink "a" 1
                                ++ "</p></li>"
                                ++ "<li id=\"user-content-fn-b\"><p>B"
                                ++ backLink "b" 2
                                ++ "</p></li>"
                                ++ "<li id=\"user-content-fn-c\"><p>C"
                                ++ backLink "c" 3
                                ++ "</p></li></ol></section>"
                            )
                        )
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
                    |> Expect.equal (Err [ UnresolvedLink { span = at 3, id = "posts/gone" } ])
        , test "every unresolvable link is reported" <|
            \_ ->
                renderWith noLinks
                    (root
                        [ paragraph [ sheafLink { collection = "posts", slug = "one", fragment = Nothing } ]
                        , Blockquote { position = at 1, children = [ paragraph [ sheafLink { collection = "posts", slug = "two", fragment = Nothing } ] ] }
                        ]
                    )
                    |> Expect.equal
                        (Err
                            [ UnresolvedLink { span = at 3, id = "posts/one" }
                            , UnresolvedLink { span = at 3, id = "posts/two" }
                            ]
                        )
        ]


directiveTests : Test
directiveTests =
    let
        callout : List Node -> Node
        callout children =
            ContainerDirective { position = at 4, name = "callout", attributes = [ ( "kind", "note" ) ], children = children }

        unknownComponent : String -> String -> Problem
        unknownComponent name example =
            Located
                { span = at 4
                , title = "UNKNOWN COMPONENT"
                , message = "This document uses a component named `" ++ name ++ "`, but the site has no component with that name."
                , hint = Just ("Add it to the site's `components`, such as `" ++ example ++ "`.")
                }
    in
    describe "directives"
        [ test "a container is an unknown component" <|
            \_ ->
                renderWith noLinks (root [ callout [ paragraph [ text "Careful." ] ] ])
                    |> Expect.equal (Err [ unknownComponent "callout" "Component.container \"callout\" …" ])
        , test "a leaf is an unknown component" <|
            \_ ->
                renderWith noLinks (root [ LeafDirective { position = at 4, name = "youtube", attributes = [ ( "id", "intro" ) ] } ])
                    |> Expect.equal (Err [ unknownComponent "youtube" "Component.leaf \"youtube\" …" ])
        , test "a footnote referenced only inside a container is numbered" <|
            \_ ->
                -- The footnote's own problem shows that its definition is rendered.
                renderWith noLinks
                    (root
                        [ callout [ paragraph [ reference "a" ] ]
                        , definitionOf "a" [ sheafLink { collection = "posts", slug = "gone", fragment = Nothing } ]
                        ]
                    )
                    |> Expect.equal
                        (Err
                            [ unknownComponent "callout" "Component.container \"callout\" …"
                            , UnresolvedLink { span = at 3, id = "posts/gone" }
                            ]
                        )
        ]


fixtureTests : Test
fixtureTests =
    let
        trees : Result Decode.Error (List Node)
        trees =
            Decode.decodeString Protocol.requestDecoder ProtocolFixtures.allNodesRequest
                |> Result.map (.documents >> List.map .tree)

        renderTree : Node -> Result (List Problem) String
        renderTree tree =
            Markdown.fromNode tree
                |> Markdown.render
                    { resolve = helloWorldAt "/blog/posts/hello-world/"
                    , components = Internal.byName [ calloutComponent, youtubeComponent ]
                    }
                |> Result.map (List.map (InternalHtml.resolveUrls underBlog >> Html.toString) >> String.concat)

        underBlog : Url -> Maybe String
        underBlog url =
            case url of
                SitePath path ->
                    Just ("/blog" ++ path)

                _ ->
                    Nothing
    in
    describe "a decoded request"
        [ test "every node type renders" <|
            \_ ->
                trees
                    |> Result.map (List.map renderTree)
                    |> Expect.equal (Ok [ Ok allNodesHtml ])
        ]


calloutComponent : Component
calloutComponent =
    Component.container "callout"
        (Component.succeed (\kind classes -> String.join " " ("callout" :: kind :: List.filterMap identity [ classes ]))
            |> Component.required "kind" Component.string
            |> Component.optional "class" Component.string
        )
        (\classes -> Html.aside [ Attributes.class classes ])


youtubeComponent : Component
youtubeComponent =
    Component.leaf "youtube"
        (Component.succeed identity |> Component.required "id" Component.string)
        (\id -> Html.div [ Attributes.id id ] [])


allNodesHtml : String
allNodesHtml =
    String.concat
        [ "<h2 id=\"intro\">Intro <a class=\"heading-link\" href=\"#intro\" aria-labelledby=\"intro\">#</a></h2>"
        , "<p>Plain <em>em</em> <strong>strong</strong> <del>del</del> <code>x &lt; y</code><br>"
        , "<a href=\"https://example.com\" title=\"Example\">ext</a> "
        , "<a href=\"/blog/posts/hello-world/#setup\">setup</a> "
        , "<picture><source type=\"image/webp\" srcset=\"/blog/_sheaf/images/36454e773ed1eac0-480.webp 480w, /blog/_sheaf/images/36454e773ed1eac0-600.webp 600w\" sizes=\"(min-width: 600px) 600px, 100vw\">"
        , "<img src=\"/blog/_sheaf/images/36454e773ed1eac0-600.png\" srcset=\"/blog/_sheaf/images/36454e773ed1eac0-480.png 480w, /blog/_sheaf/images/36454e773ed1eac0-600.png 600w\" sizes=\"(min-width: 600px) 600px, 100vw\""
        , " width=\"600\" height=\"400\" alt=\"A cat\" loading=\"lazy\" decoding=\"async\" title=\"Cat\"></picture> note"
        , "<sup><a href=\"#user-content-fn-note\" id=\"user-content-fnref-note\" data-footnote-ref>1</a></sup></p>"
        , "<pre class=\"shiki\" style=\"" ++ blockStyle ++ "\" tabindex=\"0\"><code class=\"language-elm\"><span class=\"line\">"
        , "<span style=\"color:#6F42C1;--shiki-dark:#B392F0\">x</span><span style=\"color:#24292E;--shiki-dark:#E1E4E8\"> </span>"
        , "<span style=\"color:#D73A49;--shiki-dark:#F97583\">=</span><span style=\"color:#24292E;--shiki-dark:#E1E4E8\"> </span>"
        , "<span style=\"color:#005CC5;--shiki-dark:#79B8FF\">1</span></span></code></pre>"
        , "<pre class=\"shiki\" style=\"" ++ blockStyle ++ "\" tabindex=\"0\"><code><span class=\"line\"><span>plain</span></span></code></pre>"
        , "<blockquote><p>quoted</p></blockquote>"
        , "<ol start=\"3\"><li class=\"task-list-item\"><input type=\"checkbox\" checked disabled> done</li>"
        , "<li class=\"task-list-item\"><input type=\"checkbox\" disabled> todo</li><li>plain</li></ol>"
        , "<ul><li><p>loose</p></li><li><p>list</p></li></ul>"
        , "<hr>"
        , "<table><thead><tr><th style=\"text-align: left\">A</th><th style=\"text-align: center\">B</th>"
        , "<th style=\"text-align: right\">C</th><th>D</th></tr></thead>"
        , "<tbody><tr><td style=\"text-align: left\">1</td><td style=\"text-align: center\">2</td>"
        , "<td style=\"text-align: right\">3</td><td>4</td></tr></tbody></table>"
        , "<aside class=\"callout note wide\"><p>Inside a callout.</p></aside>"
        , "<div id=\"intro\"></div>"
        , "<section data-footnotes class=\"footnotes\"><ol><li id=\"user-content-fn-note\"><p>The note."
        , backLink "note" 1
        , "</p></li></ol></section>"
        ]
