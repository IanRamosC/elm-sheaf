module Sheaf.Internal.Markdown exposing (Body, Context, Problem(..), fromNode, render)

{-| A document's Markdown body, and its renderer.

It is not exposed by the package so that only the host's decoded documents can
become a `Body`.

@docs Body, Context, Problem, fromNode, render

-}

import Dict exposing (Dict)
import Sheaf.Html as Html exposing (Html)
import Sheaf.Html.Attributes as Attributes
import Sheaf.Internal.Html as Internal
import Sheaf.Internal.Protocol exposing (Alignment(..), Node(..), Span)
import Sheaf.Ref as Ref exposing (Ref)


{-| The tree of one document.
-}
type Body
    = Body Node


{-| What rendering needs from the rest of the site. `resolve` gives the URL of
a document, or `Nothing` when it has no page.
-}
type alias Context =
    { resolve : Ref -> Maybe String
    }


{-| Why a body could not be rendered, and where in it.

An `UnresolvedLink` is a link to a document that has no page; `id` is the
target as `"<collection>/<slug>"`. The caller knows why there is no page, so it
writes the diagnostic. A `Located` problem is already a whole diagnostic.

-}
type Problem
    = UnresolvedLink { span : Span, id : String }
    | Located { span : Span, title : String, message : String, hint : Maybe String }


{-| A body from the root of a decoded tree.
-}
fromNode : Node -> Body
fromNode =
    Body


{-| The context, with the footnotes of the whole document, because a
reference anywhere may point to any of them.
-}
type alias Scope =
    { resolve : Ref -> Maybe String
    , footnotes : Dict String Footnote
    }


{-| A footnote that is both referenced and defined. Only these are rendered:
a definition nobody references is dropped, and a reference to nothing stays
as the text that was written.
-}
type alias Footnote =
    { id : String
    , number : Int
    , firstReference : Span
    , content : List Node
    }


type alias Rendered =
    Result (List Problem) (List Html)


{-| Turn a body into HTML, or every problem in it, not just the first.

Code blocks become `pre > code.language-<lang>`, headings get their `id`,
task-list items get a disabled checkbox and footnotes are laid out as GitHub
does.

-}
render : Context -> Body -> Result (List Problem) (List Html)
render context (Body tree) =
    let
        scope : Scope
        scope =
            { resolve = context.resolve, footnotes = footnotesOf tree }
    in
    merge (renderNode scope tree) (renderFootnotes scope)



-- COMBINING RESULTS


{-| Joins two renderings, keeping the problems of both so that one pass
reports every problem.
-}
merge : Rendered -> Rendered -> Rendered
merge left right =
    case ( left, right ) of
        ( Ok first, Ok second ) ->
            Ok (first ++ second)

        ( Err first, Err second ) ->
            Err (first ++ second)

        ( Err problems, Ok _ ) ->
            Err problems

        ( Ok _, Err problems ) ->
            Err problems


combine : List Rendered -> Rendered
combine =
    List.foldl (\next soFar -> merge soFar next) (Ok [])


renderNodes : Scope -> List Node -> Rendered
renderNodes scope nodes =
    combine (List.map (renderNode scope) nodes)


{-| An element around rendered children.
-}
element : (List Html -> Html) -> Rendered -> Rendered
element make children =
    Result.map (\inner -> [ make inner ]) children



-- NODES


renderNode : Scope -> Node -> Rendered
renderNode scope node =
    case node of
        Root container ->
            renderNodes scope container.children

        Paragraph container ->
            element (Html.p []) (renderNodes scope container.children)

        Heading heading ->
            element (headingElement heading.depth [ Attributes.id heading.id ]) (renderNodes scope heading.children)

        Text text ->
            Ok [ Html.text text.value ]

        Emphasis container ->
            element (Html.em []) (renderNodes scope container.children)

        Strong container ->
            element (Html.strong []) (renderNodes scope container.children)

        Delete container ->
            element (Html.del []) (renderNodes scope container.children)

        InlineCode code ->
            Ok [ Html.code [] [ Html.text code.value ] ]

        Code block ->
            Ok [ codeBlock block.lang block.value ]

        Blockquote container ->
            element (Html.blockquote []) (renderNodes scope container.children)

        ListBlock list ->
            element (listElement list) (combine (List.map (renderListItem scope list.spread) list.children))

        ListItem item ->
            renderListItem scope True (ListItem item)

        ThematicBreak _ ->
            Ok [ Html.hr [] [] ]

        Break _ ->
            Ok [ Html.br [] [] ]

        Link link ->
            element (Html.a (withTitle link.title [ Attributes.href link.url ])) (renderNodes scope link.children)

        SheafLink link ->
            renderSheafLink scope link

        Image image ->
            Ok [ Html.img (withTitle image.title [ Attributes.src image.url, Attributes.alt image.alt ]) [] ]

        Table table ->
            renderTable scope table.align table.children

        TableRow container ->
            element (Html.tr []) (renderNodes scope container.children)

        TableCell container ->
            element (Html.td []) (renderNodes scope container.children)

        FootnoteDefinition _ ->
            Ok []

        FootnoteReference reference ->
            Ok [ footnoteReference scope reference ]


headingElement : Int -> List Html.Attribute -> List Html -> Html
headingElement depth =
    case depth of
        1 ->
            Html.h1

        2 ->
            Html.h2

        3 ->
            Html.h3

        4 ->
            Html.h4

        5 ->
            Html.h5

        _ ->
            Html.h6


withTitle : Maybe String -> List Html.Attribute -> List Html.Attribute
withTitle title attributes =
    attributes ++ List.filterMap identity [ Maybe.map Attributes.title title ]


{-| A trailing newline, as other Markdown renderers emit, so the code ends on
its own line.
-}
codeBlock : Maybe String -> String -> Html
codeBlock language source =
    let
        languageClass : List Html.Attribute
        languageClass =
            case language of
                Just name ->
                    [ Attributes.class ("language-" ++ name) ]

                Nothing ->
                    []
    in
    Html.pre [] [ Html.code languageClass [ Html.text (source ++ "\n") ] ]


renderSheafLink :
    Scope
    -> { a | position : Span, collection : String, slug : String, fragment : Maybe String, title : Maybe String, children : List Node }
    -> Rendered
renderSheafLink scope link =
    let
        id : String
        id =
            link.collection ++ "/" ++ link.slug
    in
    case scope.resolve (Ref.fromId id) of
        Just url ->
            element
                (Html.a (withTitle link.title [ Attributes.href (url ++ fragmentSuffix link.fragment) ]))
                (renderNodes scope link.children)

        Nothing ->
            Err [ UnresolvedLink { span = link.position, id = id } ]


fragmentSuffix : Maybe String -> String
fragmentSuffix fragment =
    case fragment of
        Just name ->
            "#" ++ name

        Nothing ->
            ""



-- LISTS


listElement : { a | ordered : Bool, start : Maybe Int } -> List Html -> Html
listElement list =
    if list.ordered then
        case list.start of
            Just first ->
                if first == 1 then
                    Html.ol []

                else
                    Html.ol [ Attributes.attribute "start" (String.fromInt first) ]

            Nothing ->
                Html.ol []

    else
        Html.ul []


{-| In a tight list the items hold their text directly, not in paragraphs.
-}
renderListItem : Scope -> Bool -> Node -> Rendered
renderListItem scope spread node =
    case node of
        ListItem item ->
            let
                content : Rendered
                content =
                    if spread then
                        renderNodes scope item.children

                    else
                        combine (List.map (renderTightBlock scope) item.children)
            in
            case item.checked of
                Just isChecked ->
                    element (Html.li [ Attributes.class "task-list-item" ])
                        (Result.map (\inner -> checkbox isChecked :: Html.text " " :: inner) content)

                Nothing ->
                    element (Html.li []) content

        other ->
            renderNode scope other


renderTightBlock : Scope -> Node -> Rendered
renderTightBlock scope node =
    case node of
        Paragraph container ->
            renderNodes scope container.children

        other ->
            renderNode scope other


checkbox : Bool -> Html
checkbox isChecked =
    Html.input [ Attributes.type_ "checkbox", Attributes.checked isChecked, Attributes.disabled True ] []



-- TABLES


renderTable : Scope -> List (Maybe Alignment) -> List Node -> Rendered
renderTable scope alignments rows =
    case rows of
        header :: body ->
            let
                head : Rendered
                head =
                    element (Html.thead []) (renderRow scope Html.th alignments header)

                bodyRows : Rendered
                bodyRows =
                    if List.isEmpty body then
                        Ok []

                    else
                        element (Html.tbody []) (combine (List.map (renderRow scope Html.td alignments) body))
            in
            element (Html.table []) (merge head bodyRows)

        [] ->
            element (Html.table []) (Ok [])


renderRow : Scope -> (List Html.Attribute -> List Html -> Html) -> List (Maybe Alignment) -> Node -> Rendered
renderRow scope cellElement alignments row =
    case row of
        TableRow container ->
            element (Html.tr [])
                (combine
                    (List.indexedMap
                        (\column cell -> renderCell scope cellElement (alignmentOf column alignments) cell)
                        container.children
                    )
                )

        other ->
            renderNode scope other


renderCell : Scope -> (List Html.Attribute -> List Html -> Html) -> Maybe Alignment -> Node -> Rendered
renderCell scope cellElement alignment cell =
    case cell of
        TableCell container ->
            element (cellElement (alignmentStyle alignment)) (renderNodes scope container.children)

        other ->
            renderNode scope other


alignmentOf : Int -> List (Maybe Alignment) -> Maybe Alignment
alignmentOf column alignments =
    alignments
        |> List.drop column
        |> List.head
        |> Maybe.andThen identity


alignmentStyle : Maybe Alignment -> List Html.Attribute
alignmentStyle alignment =
    case alignment of
        Just AlignLeft ->
            [ textAlign "left" ]

        Just AlignCenter ->
            [ textAlign "center" ]

        Just AlignRight ->
            [ textAlign "right" ]

        Nothing ->
            []


textAlign : String -> Html.Attribute
textAlign side =
    Attributes.attribute "style" ("text-align: " ++ side)



-- FOOTNOTES


{-| Footnotes are numbered by their first reference, as on GitHub. Identifiers
are only lower-cased, which keeps them valid in an `id` and a fragment.
-}
footnotesOf : Node -> Dict String Footnote
footnotesOf tree =
    let
        nodes : List Node
        nodes =
            descendants tree

        -- The first definition of an identifier wins, so the list is reversed
        -- because `Dict.fromList` keeps the last.
        definitions : Dict String (List Node)
        definitions =
            nodes
                |> List.filterMap
                    (\node ->
                        case node of
                            FootnoteDefinition definition ->
                                Just ( footnoteId definition.identifier, definition.children )

                            _ ->
                                Nothing
                    )
                |> List.reverse
                |> Dict.fromList

        addReference : { a | position : Span, identifier : String } -> Dict String Footnote -> Dict String Footnote
        addReference reference footnotes =
            let
                id : String
                id =
                    footnoteId reference.identifier
            in
            case ( Dict.get id footnotes, Dict.get id definitions ) of
                ( Nothing, Just content ) ->
                    Dict.insert id
                        { id = id
                        , number = Dict.size footnotes + 1
                        , firstReference = reference.position
                        , content = content
                        }
                        footnotes

                _ ->
                    footnotes
    in
    nodes
        |> List.filterMap
            (\node ->
                case node of
                    FootnoteReference reference ->
                        Just reference

                    _ ->
                        Nothing
            )
        |> List.foldl addReference Dict.empty


footnoteId : String -> String
footnoteId =
    String.toLower


descendants : Node -> List Node
descendants node =
    node :: List.concatMap descendants (childrenOf node)


childrenOf : Node -> List Node
childrenOf node =
    case node of
        Root container ->
            container.children

        Paragraph container ->
            container.children

        Heading heading ->
            heading.children

        Emphasis container ->
            container.children

        Strong container ->
            container.children

        Delete container ->
            container.children

        Blockquote container ->
            container.children

        ListBlock list ->
            list.children

        ListItem item ->
            item.children

        Link link ->
            link.children

        SheafLink link ->
            link.children

        Table table ->
            table.children

        TableRow container ->
            container.children

        TableCell container ->
            container.children

        FootnoteDefinition definition ->
            definition.children

        Text _ ->
            []

        InlineCode _ ->
            []

        Code _ ->
            []

        ThematicBreak _ ->
            []

        Break _ ->
            []

        Image _ ->
            []

        FootnoteReference _ ->
            []


footnoteReference : Scope -> { position : Span, identifier : String } -> Html
footnoteReference scope reference =
    case Dict.get (footnoteId reference.identifier) scope.footnotes of
        Just footnote ->
            -- Later references to the same footnote must not repeat the id,
            -- so the back link always returns to the first.
            Html.sup []
                [ Html.a
                    (List.concat
                        [ [ Attributes.href ("#user-content-fn-" ++ footnote.id) ]
                        , if reference.position == footnote.firstReference then
                            [ Attributes.id ("user-content-fnref-" ++ footnote.id) ]

                          else
                            []
                        , [ Internal.booleanAttribute "data-footnote-ref" True ]
                        ]
                    )
                    [ Html.text (String.fromInt footnote.number) ]
                ]

        Nothing ->
            Html.text ("[^" ++ reference.identifier ++ "]")


renderFootnotes : Scope -> Rendered
renderFootnotes scope =
    if Dict.isEmpty scope.footnotes then
        Ok []

    else
        scope.footnotes
            |> Dict.values
            |> List.sortBy .number
            |> List.map (renderFootnote scope)
            |> combine
            |> element
                (\items ->
                    Html.section
                        [ Internal.booleanAttribute "data-footnotes" True, Attributes.class "footnotes" ]
                        [ Html.ol [] items ]
                )


{-| The back link goes at the end of the last paragraph, as on GitHub.
-}
renderFootnote : Scope -> Footnote -> Rendered
renderFootnote scope footnote =
    let
        backLink : List Html
        backLink =
            [ Html.text " "
            , Html.a
                [ Attributes.href ("#user-content-fnref-" ++ footnote.id)
                , Internal.booleanAttribute "data-footnote-backref" True
                , Attributes.attribute "aria-label" ("Back to reference " ++ String.fromInt footnote.number)
                ]
                [ Html.text "↩" ]
            ]

        content : Rendered
        content =
            case List.reverse footnote.content of
                (Paragraph last) :: before ->
                    merge
                        (renderNodes scope (List.reverse before))
                        (element (Html.p []) (Result.map (\inner -> inner ++ backLink) (renderNodes scope last.children)))

                _ ->
                    merge (renderNodes scope footnote.content) (Ok [ Html.p [] backLink ])
    in
    element (Html.li [ Attributes.id ("user-content-fn-" ++ footnote.id) ]) content
