module Sheaf.ComponentTest exposing (suite)

import Expect
import RenderFixtures exposing (metadata, page, post, postRoute, request, span)
import Sheaf
import Sheaf.Component as Component exposing (Component)
import Sheaf.Html as Html exposing (Html)
import Sheaf.Html.Attributes as Attributes
import Sheaf.Internal.Component as Internal
import Sheaf.Internal.Markdown as Markdown exposing (Problem(..))
import Sheaf.Internal.Protocol as Protocol exposing (Diagnostic, Node(..), Severity(..))
import Sheaf.Internal.Render as Render
import Sheaf.Ref as Ref exposing (Ref)
import Sheaf.Route as Route
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Sheaf.Component"
        [ renderingTests
        , nestingTests
        , unknownComponentTests
        , wrongKindTests
        , attributeTests
        , valueTests
        , siteTests
        ]



-- COMPONENTS


type Kind
    = Note
    | Warning


callout : Component
callout =
    Component.container "callout"
        (Component.succeed identity
            |> Component.required "kind" (Component.oneOf [ ( "note", Note ), ( "warning", Warning ) ])
        )
        calloutView


calloutView : Kind -> List Html -> Html
calloutView kind children =
    let
        name : String
        name =
            case kind of
                Note ->
                    "note"

                Warning ->
                    "warning"
    in
    Html.aside [ Attributes.class ("callout " ++ name) ] children


type alias Video =
    { id : String
    , width : Int
    , title : Maybe String
    }


youtube : Component
youtube =
    Component.leaf "youtube"
        (Component.succeed Video
            |> Component.required "id" Component.string
            |> Component.withDefault "width" 560 Component.int
            |> Component.optional "title" Component.string
        )
        (\video ->
            Html.div
                (Attributes.id video.id
                    :: Attributes.width video.width
                    :: List.map Attributes.title (List.filterMap identity [ video.title ])
                )
                []
        )



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


container : String -> List ( String, String ) -> List Node -> Node
container name attributes children =
    ContainerDirective { position = at 4, name = name, attributes = attributes, children = children }


leaf : String -> List ( String, String ) -> Node
leaf name attributes =
    LeafDirective { position = at 6, name = name, attributes = attributes }


warning : List Node -> Node
warning =
    container "callout" [ ( "kind", "warning" ) ]


reference : String -> Node
reference identifier =
    FootnoteReference { position = at 1, identifier = identifier }


definition : String -> String -> Node
definition identifier content =
    FootnoteDefinition { position = at 9, identifier = identifier, children = [ paragraph [ text content ] ] }



-- RENDERING


render : List Component -> List Node -> Result (List Problem) String
render components nodes =
    Root { position = at 1, children = nodes }
        |> Markdown.fromNode
        |> Markdown.render { resolve = postsB, components = Internal.byName components }
        |> Result.map (List.map Html.toString >> String.concat)


postsB : Ref -> Maybe String
postsB ref =
    if Ref.id ref == "posts/b" then
        Just "/blog/posts/b/"

    else
        Nothing


located : Int -> String -> String -> Maybe String -> Problem
located line title message hint =
    Located { span = at line, title = title, message = message, hint = hint }


renderingTests : Test
renderingTests =
    describe "rendering"
        [ test "a container gets its attributes and its rendered children, with links resolved" <|
            \_ ->
                render [ callout ]
                    [ warning
                        [ paragraph
                            [ SheafLink { position = at 5, collection = "posts", slug = "b", fragment = Nothing, title = Nothing, children = [ text "B" ] } ]
                        ]
                    ]
                    |> Expect.equal (Ok "<aside class=\"callout warning\"><p><a href=\"/blog/posts/b/\">B</a></p></aside>")
        , test "a leaf gets its attributes, with defaults for those left out" <|
            \_ ->
                render [ youtube ] [ leaf "youtube" [ ( "id", "abc" ) ] ]
                    |> Expect.equal (Ok "<div id=\"abc\" width=\"560\"></div>")
        , test "a problem inside a container is reported" <|
            \_ ->
                render [ callout ]
                    [ warning [ paragraph [ SheafLink { position = at 5, collection = "posts", slug = "gone", fragment = Nothing, title = Nothing, children = [] } ] ] ]
                    |> Expect.equal (Err [ UnresolvedLink { span = at 5, id = "posts/gone" } ])
        ]


nestingTests : Test
nestingTests =
    describe "nesting"
        [ test "a container inside a list item" <|
            \_ ->
                render [ callout ]
                    [ ListBlock
                        { position = at 1
                        , ordered = False
                        , start = Nothing
                        , spread = False
                        , children = [ ListItem { position = at 1, checked = Nothing, children = [ warning [ paragraph [ text "a" ] ] ] } ]
                        }
                    ]
                    |> Expect.equal (Ok "<ul><li><aside class=\"callout warning\"><p>a</p></aside></li></ul>")
        , test "a container inside another" <|
            \_ ->
                render [ callout ] [ warning [ container "callout" [ ( "kind", "note" ) ] [ paragraph [ text "a" ] ] ] ]
                    |> Expect.equal (Ok "<aside class=\"callout warning\"><aside class=\"callout note\"><p>a</p></aside></aside>")
        , test "a footnote referenced inside a container is numbered with the rest" <|
            \_ ->
                render [ callout ]
                    [ paragraph [ reference "a" ]
                    , warning [ paragraph [ reference "b" ] ]
                    , definition "a" "A"
                    , definition "b" "B"
                    ]
                    |> Result.map (String.contains "<aside class=\"callout warning\"><p><sup><a href=\"#user-content-fn-b\" id=\"user-content-fnref-b\" data-footnote-ref>2</a></sup></p></aside>")
                    |> Expect.equal (Ok True)
        ]


unknownComponentTests : Test
unknownComponentTests =
    describe "unknown components"
        [ test "a misspelled name suggests the close one" <|
            \_ ->
                render [ callout, youtube ] [ container "calout" [ ( "kind", "note" ) ] [] ]
                    |> Expect.equal
                        (Err
                            [ located 4
                                "UNKNOWN COMPONENT"
                                "This document uses a component named `calout`, but the site has no component with that name."
                                (Just "Did you mean `callout`?")
                            ]
                        )
        , test "a name close to none says how to add it" <|
            \_ ->
                render [ youtube ] [ container "calout" [] [] ]
                    |> Expect.equal
                        (Err
                            [ located 4
                                "UNKNOWN COMPONENT"
                                "This document uses a component named `calout`, but the site has no component with that name."
                                (Just "Add it to the site's `components`, such as `Component.container \"calout\" …`.")
                            ]
                        )
        , test "the children of an unknown container are still checked" <|
            \_ ->
                render [] [ container "callout" [] [ paragraph [ SheafLink { position = at 5, collection = "posts", slug = "gone", fragment = Nothing, title = Nothing, children = [] } ] ] ]
                    |> Result.mapError List.length
                    |> Expect.equal (Err 2)
        ]


wrongKindTests : Test
wrongKindTests =
    describe "the wrong kind of component"
        [ test "a leaf used as a container" <|
            \_ ->
                render [ youtube ] [ container "youtube" [ ( "id", "abc" ) ] [] ]
                    |> Expect.equal
                        (Err
                            [ located 4
                                "WRONG COMPONENT KIND"
                                "`youtube` is a leaf component, written on one line as `::youtube{…}`, but here it is used as a container, `:::youtube`."
                                Nothing
                            ]
                        )
        , test "a container used as a leaf" <|
            \_ ->
                render [ callout ] [ leaf "callout" [ ( "kind", "note" ) ] ]
                    |> Expect.equal
                        (Err
                            [ located 6
                                "WRONG COMPONENT KIND"
                                "`callout` is a container component, written around its content as `:::callout{…}` and `:::`, but here it is used as a leaf, `::callout`."
                                Nothing
                            ]
                        )
        ]


attributeTests : Test
attributeTests =
    describe "attributes"
        [ test "a value that is not one of the choices" <|
            \_ ->
                render [ callout ] [ container "callout" [ ( "kind", "danger" ) ] [] ]
                    |> Expect.equal
                        (Err
                            [ located 4
                                "BAD ATTRIBUTE"
                                "The `kind` attribute of `callout` should be one of `note`, `warning`, but it is `danger`."
                                Nothing
                            ]
                        )
        , test "a missing attribute" <|
            \_ ->
                render [ callout ] [ container "callout" [] [] ]
                    |> Expect.equal
                        (Err
                            [ located 4
                                "MISSING ATTRIBUTE"
                                "This `callout` has no `kind` attribute, which it needs."
                                (Just "Write it in the braces, such as `:::callout{kind=\"…\"}`.")
                            ]
                        )
        , test "every problem of one directive is reported, at its span" <|
            \_ ->
                render [ callout ] [ container "callout" [ ( "knd", "note" ) ] [] ]
                    |> Expect.equal
                        (Err
                            [ located 4
                                "MISSING ATTRIBUTE"
                                "This `callout` has no `kind` attribute, which it needs."
                                (Just "Write it in the braces, such as `:::callout{kind=\"…\"}`.")
                            , located 4
                                "UNKNOWN ATTRIBUTE"
                                "`callout` has no attribute named `knd`."
                                (Just "Did you mean `kind`?")
                            ]
                        )
        , test "an unknown attribute close to none lists the known ones" <|
            \_ ->
                render [ youtube ] [ leaf "youtube" [ ( "id", "abc" ), ( "class", "wide" ) ] ]
                    |> Expect.equal
                        (Err
                            [ located 6
                                "UNKNOWN ATTRIBUTE"
                                "`youtube` has no attribute named `class`."
                                (Just "The attributes of `youtube` are `id`, `width` and `title`.")
                            ]
                        )
        , test "a component without attributes says so" <|
            \_ ->
                render [ Component.leaf "divider" (Component.succeed ()) (\() -> Html.hr [] []) ] [ leaf "divider" [ ( "wide", "" ) ] ]
                    |> Expect.equal
                        (Err
                            [ located 6
                                "UNKNOWN ATTRIBUTE"
                                "`divider` has no attribute named `wide`."
                                (Just "`divider` takes no attributes.")
                            ]
                        )
        ]


valueTests : Test
valueTests =
    let
        number : Component.Value Int -> String -> Result (List Problem) String
        number value written =
            render
                [ Component.leaf "count"
                    (Component.succeed identity |> Component.required "n" value)
                    (\n -> Html.text (String.fromInt n))
                ]
                [ leaf "count" [ ( "n", written ) ] ]
    in
    describe "values"
        [ test "an optional attribute that is written" <|
            \_ ->
                render [ youtube ] [ leaf "youtube" [ ( "id", "abc" ), ( "width", "640" ), ( "title", "Intro" ) ] ]
                    |> Expect.equal (Ok "<div id=\"abc\" width=\"640\" title=\"Intro\"></div>")
        , test "an int" <|
            \_ ->
                number Component.int "42"
                    |> Expect.equal (Ok "42")
        , test "a value that is not an int" <|
            \_ ->
                number Component.int "wide"
                    |> Expect.equal
                        (Err [ located 6 "BAD ATTRIBUTE" "The `n` attribute of `count` should be a whole number, but it is `wide`." Nothing ])
        , test "an empty value" <|
            \_ ->
                number Component.int ""
                    |> Expect.equal
                        (Err [ located 6 "BAD ATTRIBUTE" "The `n` attribute of `count` should be a whole number, but it is empty." Nothing ])
        , test "map transforms a value" <|
            \_ ->
                number (Component.map String.length Component.string) "four"
                    |> Expect.equal (Ok "4")
        , test "validate's message is the diagnostic's message" <|
            \_ ->
                number
                    (Component.int
                        |> Component.validate
                            (\n ->
                                if n > 0 then
                                    Ok n

                                else
                                    Err "The `n` of `count` must be positive."
                            )
                    )
                    "0"
                    |> Expect.equal (Err [ located 6 "BAD ATTRIBUTE" "The `n` of `count` must be positive." Nothing ])
        ]



-- THE SITE


siteTests : Test
siteTests =
    let
        renderWith : Sheaf.Site -> List Diagnostic
        renderWith site =
            request [] []
                |> Render.render site
                |> .diagnostics

        withComponents : List Component -> Sheaf.Site
        withComponents components =
            Sheaf.site { metadata = metadata, routes = [ Route.single "/" (page []) ], feeds = [], components = components }

        siteError : String -> String -> String -> Diagnostic
        siteError title message hint =
            { severity = Error
            , title = title
            , message = message
            , sourcePath = Nothing
            , span = Nothing
            , hint = Just hint
            }

        badName : String -> Diagnostic
        badName name =
            siteError "BAD COMPONENT NAME"
                ("The site has a component named `" ++ name ++ "`, which Markdown cannot use as a name.")
                "A component's name starts with a letter, followed by letters, digits, `-` and `_`, such as `callout` or `video-embed`."
    in
    describe "the site's components"
        [ test "two components with one name are reported once" <|
            \_ ->
                renderWith (withComponents [ callout, youtube, callout, callout ])
                    |> Expect.equal
                        [ siteError "DUPLICATE COMPONENT"
                            "The site has more than one component named `callout`."
                            "Markdown finds a component by its name, so each name can be used once."
                        ]
        , test "a name Markdown cannot write is reported" <|
            \_ ->
                renderWith
                    (withComponents
                        [ Component.leaf "9lives" (Component.succeed ()) (\() -> Html.text "")
                        , Component.leaf "call out" (Component.succeed ()) (\() -> Html.text "")
                        , Component.leaf "video-embed_2" (Component.succeed ()) (\() -> Html.text "")
                        ]
                    )
                    |> Expect.equal [ badName "9lives", badName "call out" ]
        , test "withComponents adds components the site's documents use" <|
            \_ ->
                let
                    embedding : RenderFixtures.Source
                    embedding =
                        post "hello-world"
                in
                request [ "posts" ] [ { embedding | body = [ RenderFixtures.leafDirective "youtube" (span 4 1 18) ] } ]
                    |> Render.render
                        (Sheaf.site { metadata = metadata, routes = [ postRoute ], feeds = [], components = [] }
                            |> Sheaf.withComponents [ Component.leaf "youtube" (Component.succeed ()) (\() -> Html.text "video") ]
                        )
                    |> RenderFixtures.bodyAt "posts/hello-world/index.html"
                    |> Expect.equal (Just "<article><h1>hello-world</h1>video</article>")
        ]
