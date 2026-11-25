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

`references` holds where each reference is, in the order they are rendered,
because each one gets its own id and its own back link.

-}
type alias Footnote =
    { id : String
    , number : Int
    , references : List Span
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

        ContainerDirective directive ->
            merge
                (unknownComponent directive ("Component.container \"" ++ directive.name ++ "\" …"))
                (renderNodes scope directive.children)

        LeafDirective directive ->
            unknownComponent directive ("Component.leaf \"" ++ directive.name ++ "\" …")


{-| Sites have no components yet, so every directive names an unknown one.
-}
unknownComponent : { a | position : Span, name : String } -> String -> Rendered
unknownComponent directive example =
    Err
        [ Located
            { span = directive.position
            , title = "UNKNOWN COMPONENT"
            , message = "This document uses a component named `" ++ directive.name ++ "`, but the site has no component with that name."
            , hint = Just ("Add it to the site's `components`, such as `" ++ example ++ "`.")
            }
        ]


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


{-| In a tight list the items hold their text directly, not in paragraphs. In
a loose one a task item's checkbox goes inside its first paragraph, as on
GitHub, so that it sits on the line of the text.
-}
renderListItem : Scope -> Bool -> Node -> Rendered
renderListItem scope spread node =
    case node of
        ListItem item ->
            case ( item.checked, spread, item.children ) of
                ( Just isChecked, True, (Paragraph first) :: rest ) ->
                    element (Html.li [ Attributes.class "task-list-item" ])
                        (merge
                            (element (Html.p []) (withCheckbox isChecked (renderNodes scope first.children)))
                            (renderNodes scope rest)
                        )

                ( Just isChecked, _, _ ) ->
                    element (Html.li [ Attributes.class "task-list-item" ])
                        (withCheckbox isChecked (renderItemContent scope spread item.children))

                ( Nothing, _, _ ) ->
                    element (Html.li []) (renderItemContent scope spread item.children)

        other ->
            renderNode scope other


renderItemContent : Scope -> Bool -> List Node -> Rendered
renderItemContent scope spread children =
    if spread then
        renderNodes scope children

    else
        combine (List.map (renderTightBlock scope) children)


renderTightBlock : Scope -> Node -> Rendered
renderTightBlock scope node =
    case node of
        Paragraph container ->
            renderNodes scope container.children

        other ->
            renderNode scope other


withCheckbox : Bool -> Rendered -> Rendered
withCheckbox isChecked =
    Result.map
        (\inner ->
            Html.input [ Attributes.type_ "checkbox", Attributes.checked isChecked, Attributes.disabled True ] []
                :: Html.text " "
                :: inner
        )



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


{-| Footnotes are numbered by their first reference, as on GitHub. The body
is read first, then each rendered definition in turn, which is the order they
appear on the page. A definition nobody references is never read, so the
references in it do not count.

Identifiers arrive URL-safe from the host and are only lower-cased, which
keeps them valid in an `id` and a fragment.

-}
footnotesOf : Node -> Dict String Footnote
footnotesOf tree =
    let
        -- The first definition of an identifier wins, so the list is reversed
        -- because `Dict.fromList` keeps the last.
        definitions : Dict String (List Node)
        definitions =
            descendants tree
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

        addReference :
            { position : Span, identifier : String }
            -> ( Dict String Footnote, List (List Node) )
            -> ( Dict String Footnote, List (List Node) )
        addReference reference ( footnotes, newlyNumbered ) =
            let
                id : String
                id =
                    footnoteId reference.identifier
            in
            case ( Dict.get id footnotes, Dict.get id definitions ) of
                ( Just footnote, _ ) ->
                    ( Dict.insert id { footnote | references = footnote.references ++ [ reference.position ] } footnotes
                    , newlyNumbered
                    )

                ( Nothing, Just content ) ->
                    ( Dict.insert id
                        { id = id
                        , number = Dict.size footnotes + 1
                        , references = [ reference.position ]
                        , content = content
                        }
                        footnotes
                    , newlyNumbered ++ [ content ]
                    )

                ( Nothing, Nothing ) ->
                    ( footnotes, newlyNumbered )

        collect : List (List Node) -> Dict String Footnote -> Dict String Footnote
        collect toRead footnotes =
            case toRead of
                [] ->
                    footnotes

                nodes :: rest ->
                    let
                        ( withReferences, newlyNumbered ) =
                            List.foldl addReference ( footnotes, [] ) (List.concatMap referencesIn nodes)
                    in
                    collect (rest ++ newlyNumbered) withReferences
    in
    collect [ [ tree ] ] Dict.empty


{-| The references a node renders, leaving out definitions, which are rendered
apart from where they are written.
-}
referencesIn : Node -> List { position : Span, identifier : String }
referencesIn node =
    case node of
        FootnoteReference reference ->
            [ reference ]

        FootnoteDefinition _ ->
            []

        _ ->
            List.concatMap referencesIn (childrenOf node)


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

        ContainerDirective directive ->
            directive.children

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

        LeafDirective _ ->
            []


footnoteReference : Scope -> { position : Span, identifier : String } -> Html
footnoteReference scope reference =
    case Dict.get (footnoteId reference.identifier) scope.footnotes of
        Just footnote ->
            Html.sup []
                [ Html.a
                    (List.concat
                        [ [ Attributes.href ("#user-content-fn-" ++ footnote.id) ]
                        , case indexOf reference.position footnote.references of
                            Just index ->
                                [ Attributes.id (referenceId footnote index) ]

                            Nothing ->
                                []
                        , [ Internal.booleanAttribute "data-footnote-ref" True ]
                        ]
                    )
                    [ Html.text (String.fromInt footnote.number) ]
                ]

        Nothing ->
            Html.text ("[^" ++ reference.identifier ++ "]")


{-| The id of a footnote's reference, counting from 1. Only the first one goes
without a suffix, as on GitHub.
-}
referenceId : Footnote -> Int -> String
referenceId footnote index =
    if index == 1 then
        "user-content-fnref-" ++ footnote.id

    else
        "user-content-fnref-" ++ footnote.id ++ "-" ++ String.fromInt index


indexOf : a -> List a -> Maybe Int
indexOf wanted items =
    items
        |> List.indexedMap (\index item -> ( index + 1, item ))
        |> List.filter (\( _, item ) -> item == wanted)
        |> List.head
        |> Maybe.map Tuple.first


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


{-| The back links, one for each reference, go at the end of the last
paragraph, as on GitHub.
-}
renderFootnote : Scope -> Footnote -> Rendered
renderFootnote scope footnote =
    let
        backLinks : List Html
        backLinks =
            List.indexedMap (\index _ -> backLinkTo footnote (index + 1)) footnote.references
                |> List.concat

        content : Rendered
        content =
            case List.reverse footnote.content of
                (Paragraph last) :: before ->
                    merge
                        (renderNodes scope (List.reverse before))
                        (element (Html.p []) (Result.map (\inner -> inner ++ backLinks) (renderNodes scope last.children)))

                _ ->
                    merge (renderNodes scope footnote.content) (Ok [ Html.p [] backLinks ])
    in
    element (Html.li [ Attributes.id ("user-content-fn-" ++ footnote.id) ]) content


{-| Only later back links are told apart, with the index of their reference,
as on GitHub.
-}
backLinkTo : Footnote -> Int -> List Html
backLinkTo footnote index =
    let
        ( label, mark ) =
            if index == 1 then
                ( String.fromInt footnote.number, [ Html.text "↩" ] )

            else
                ( String.fromInt footnote.number ++ "-" ++ String.fromInt index
                , [ Html.text "↩", Html.sup [] [ Html.text (String.fromInt index) ] ]
                )
    in
    [ Html.text " "
    , Html.a
        [ Attributes.href ("#" ++ referenceId footnote index)
        , Internal.booleanAttribute "data-footnote-backref" True
        , Attributes.attribute "aria-label" ("Back to reference " ++ label)
        ]
        mark
    ]
