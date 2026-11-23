module Sheaf.Internal.Protocol exposing
    ( Request, Build, BuildMode(..), Document, Date
    , Span, Position, FieldPosition
    , Node(..), Container, Alignment(..)
    , requestDecoder
    , Response, Page, Diagnostic, Severity(..), encodeResponse
    )

{-| The JSON the host and the Elm worker exchange.

The types mirror `cli/src/elm/protocol.ts` and `cli/src/markdown/tree.ts`, and
`tests/fixtures/protocol/` holds JSON that both sides are tested against, so a
change to one side is a change to the other.

It is not exposed by the package.

@docs Request, Build, BuildMode, Document, Date
@docs Span, Position, FieldPosition
@docs Node, Container, Alignment
@docs requestDecoder
@docs Response, Page, Diagnostic, Severity, encodeResponse

-}

import Dict exposing (Dict)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Time



-- REQUEST


{-| Everything the host knows about the site.
-}
type alias Request =
    { build : Build
    , documents : List Document
    }


{-| How this build was invoked.
-}
type alias Build =
    { siteUrl : String
    , basePath : String
    , mode : BuildMode
    }


{-| `Drafts` builds include drafts and future-dated documents.
-}
type BuildMode
    = Production
    | Drafts


{-| One Markdown file, with its reserved frontmatter keys already resolved.
-}
type alias Document =
    { id : String
    , collection : String
    , sourcePath : String
    , slug : String
    , date : Maybe Date
    , updated : Maybe Date
    , draft : Bool
    , excluded : Bool
    , frontmatter : Decode.Value
    , frontmatterPositions : Dict String FieldPosition
    , tree : Node
    }


{-| A moment, and the calendar date as the author wrote it.
-}
type alias Date =
    { posix : Time.Posix
    , isoDate : String
    }


{-| A line and column in a source file, both counted from 1.
-}
type alias Position =
    { line : Int, column : Int }


{-| A region of a source file. The end is exclusive.
-}
type alias Span =
    { start : Position, end : Position }


{-| Where a frontmatter value sits. A list item has no key.
-}
type alias FieldPosition =
    { key : Maybe Span, value : Span }


{-| The version of the protocol this code speaks.
-}
protocolVersion : Int
protocolVersion =
    1


{-| Decodes the host's request, which must speak this protocol version.
-}
requestDecoder : Decoder Request
requestDecoder =
    Decode.field "protocolVersion" Decode.int
        |> Decode.andThen
            (\version ->
                if version == protocolVersion then
                    Decode.map2 Request
                        (Decode.field "build" buildDecoder)
                        (Decode.field "documents" (Decode.list documentDecoder))

                else
                    Decode.fail
                        ("The host speaks protocol version "
                            ++ String.fromInt version
                            ++ " but this worker speaks "
                            ++ String.fromInt protocolVersion
                        )
            )


buildDecoder : Decoder Build
buildDecoder =
    Decode.map3 Build
        (Decode.field "siteUrl" Decode.string)
        (Decode.field "basePath" Decode.string)
        (Decode.field "mode" buildModeDecoder)


buildModeDecoder : Decoder BuildMode
buildModeDecoder =
    Decode.string
        |> Decode.andThen
            (\mode ->
                case mode of
                    "production" ->
                        Decode.succeed Production

                    "drafts" ->
                        Decode.succeed Drafts

                    _ ->
                        Decode.fail ("Unknown build mode \"" ++ mode ++ "\"")
            )


documentDecoder : Decoder Document
documentDecoder =
    Decode.succeed Document
        |> andMap (Decode.field "id" Decode.string)
        |> andMap (Decode.field "collection" Decode.string)
        |> andMap (Decode.field "sourcePath" Decode.string)
        |> andMap (Decode.field "slug" Decode.string)
        |> andMap (Decode.field "date" (Decode.nullable dateDecoder))
        |> andMap (Decode.field "updated" (Decode.nullable dateDecoder))
        |> andMap (Decode.field "draft" Decode.bool)
        |> andMap (Decode.field "excluded" Decode.bool)
        |> andMap (Decode.field "frontmatter" Decode.value)
        |> andMap (Decode.field "frontmatterPositions" (Decode.dict fieldPositionDecoder))
        |> andMap (Decode.field "tree" nodeDecoder)


andMap : Decoder a -> Decoder (a -> b) -> Decoder b
andMap =
    Decode.map2 (|>)


dateDecoder : Decoder Date
dateDecoder =
    Decode.map2 Date
        (Decode.map Time.millisToPosix (Decode.field "posixMillis" Decode.int))
        (Decode.field "isoDate" Decode.string)


fieldPositionDecoder : Decoder FieldPosition
fieldPositionDecoder =
    Decode.map2 FieldPosition
        (optionalField "key" spanDecoder)
        (Decode.field "value" spanDecoder)


spanDecoder : Decoder Span
spanDecoder =
    Decode.map2 Span
        (Decode.field "start" positionDecoder)
        (Decode.field "end" positionDecoder)


positionDecoder : Decoder Position
positionDecoder =
    Decode.map2 Position
        (Decode.field "line" Decode.int)
        (Decode.field "column" Decode.int)


{-| A field the host leaves out when it has no value. Unlike `Decode.maybe`, a
field that is present but malformed is still an error.
-}
optionalField : String -> Decoder a -> Decoder (Maybe a)
optionalField name decoder =
    Decode.oneOf [ Decode.field name (Decode.succeed True), Decode.succeed False ]
        |> Decode.andThen
            (\isPresent ->
                if isPresent then
                    Decode.map Just (Decode.field name decoder)

                else
                    Decode.succeed Nothing
            )



-- MARKDOWN TREE


{-| The Markdown tree, one constructor for each `type` in `tree.ts`. Optional
fields there are `Maybe` here.
-}
type Node
    = Root Container
    | Paragraph Container
    | Heading { position : Span, depth : Int, id : String, children : List Node }
    | Text { position : Span, value : String }
    | Emphasis Container
    | Strong Container
    | Delete Container
    | InlineCode { position : Span, value : String }
    | Code { position : Span, lang : Maybe String, value : String }
    | Blockquote Container
    | ListBlock { position : Span, ordered : Bool, start : Maybe Int, spread : Bool, children : List Node }
    | ListItem { position : Span, checked : Maybe Bool, children : List Node }
    | ThematicBreak { position : Span }
    | Break { position : Span }
    | Link { position : Span, url : String, title : Maybe String, children : List Node }
    | SheafLink { position : Span, collection : String, slug : String, fragment : Maybe String, title : Maybe String, children : List Node }
    | Image { position : Span, url : String, alt : String, title : Maybe String }
    | Table { position : Span, align : List (Maybe Alignment), children : List Node }
    | TableRow Container
    | TableCell Container
    | FootnoteDefinition { position : Span, identifier : String, children : List Node }
    | FootnoteReference { position : Span, identifier : String }


{-| The fields of every node that only holds other nodes.
-}
type alias Container =
    { position : Span, children : List Node }


{-| How a table column is aligned.
-}
type Alignment
    = AlignLeft
    | AlignRight
    | AlignCenter


nodeDecoder : Decoder Node
nodeDecoder =
    Decode.field "type" Decode.string
        |> Decode.andThen nodeOfType


nodeOfType : String -> Decoder Node
nodeOfType type_ =
    case type_ of
        "root" ->
            Decode.map Root containerDecoder

        "paragraph" ->
            Decode.map Paragraph containerDecoder

        "heading" ->
            Decode.map4 (\position depth id children -> Heading { position = position, depth = depth, id = id, children = children })
                positionField
                (Decode.field "depth" Decode.int)
                (Decode.field "id" Decode.string)
                childrenField

        "text" ->
            Decode.map2 (\position value -> Text { position = position, value = value })
                positionField
                (Decode.field "value" Decode.string)

        "emphasis" ->
            Decode.map Emphasis containerDecoder

        "strong" ->
            Decode.map Strong containerDecoder

        "delete" ->
            Decode.map Delete containerDecoder

        "inlineCode" ->
            Decode.map2 (\position value -> InlineCode { position = position, value = value })
                positionField
                (Decode.field "value" Decode.string)

        "code" ->
            Decode.map3 (\position lang value -> Code { position = position, lang = lang, value = value })
                positionField
                (optionalField "lang" Decode.string)
                (Decode.field "value" Decode.string)

        "blockquote" ->
            Decode.map Blockquote containerDecoder

        "list" ->
            Decode.map5 (\position ordered start spread children -> ListBlock { position = position, ordered = ordered, start = start, spread = spread, children = children })
                positionField
                (Decode.field "ordered" Decode.bool)
                (optionalField "start" Decode.int)
                (Decode.field "spread" Decode.bool)
                childrenField

        "listItem" ->
            Decode.map3 (\position checked children -> ListItem { position = position, checked = checked, children = children })
                positionField
                (optionalField "checked" Decode.bool)
                childrenField

        "thematicBreak" ->
            Decode.map (\position -> ThematicBreak { position = position }) positionField

        "break" ->
            Decode.map (\position -> Break { position = position }) positionField

        "link" ->
            Decode.map4 (\position url title children -> Link { position = position, url = url, title = title, children = children })
                positionField
                (Decode.field "url" Decode.string)
                (optionalField "title" Decode.string)
                childrenField

        "sheafLink" ->
            Decode.succeed (\position collection slug fragment title children -> SheafLink { position = position, collection = collection, slug = slug, fragment = fragment, title = title, children = children })
                |> andMap positionField
                |> andMap (Decode.field "collection" Decode.string)
                |> andMap (Decode.field "slug" Decode.string)
                |> andMap (optionalField "fragment" Decode.string)
                |> andMap (optionalField "title" Decode.string)
                |> andMap childrenField

        "image" ->
            Decode.map4 (\position url alt title -> Image { position = position, url = url, alt = alt, title = title })
                positionField
                (Decode.field "url" Decode.string)
                (Decode.field "alt" Decode.string)
                (optionalField "title" Decode.string)

        "table" ->
            Decode.map3 (\position align children -> Table { position = position, align = align, children = children })
                positionField
                (Decode.field "align" (Decode.list (Decode.nullable alignmentDecoder)))
                childrenField

        "tableRow" ->
            Decode.map TableRow containerDecoder

        "tableCell" ->
            Decode.map TableCell containerDecoder

        "footnoteDefinition" ->
            Decode.map3 (\position identifier children -> FootnoteDefinition { position = position, identifier = identifier, children = children })
                positionField
                (Decode.field "identifier" Decode.string)
                childrenField

        "footnoteReference" ->
            Decode.map2 (\position identifier -> FootnoteReference { position = position, identifier = identifier })
                positionField
                (Decode.field "identifier" Decode.string)

        _ ->
            Decode.fail ("Unknown Markdown node type \"" ++ type_ ++ "\"")


positionField : Decoder Span
positionField =
    Decode.field "position" spanDecoder


childrenField : Decoder (List Node)
childrenField =
    Decode.field "children" (Decode.list (Decode.lazy (\_ -> nodeDecoder)))


containerDecoder : Decoder Container
containerDecoder =
    Decode.map2 Container positionField childrenField


alignmentDecoder : Decoder Alignment
alignmentDecoder =
    Decode.string
        |> Decode.andThen
            (\alignment ->
                case alignment of
                    "left" ->
                        Decode.succeed AlignLeft

                    "right" ->
                        Decode.succeed AlignRight

                    "center" ->
                        Decode.succeed AlignCenter

                    _ ->
                        Decode.fail ("Unknown table alignment \"" ++ alignment ++ "\"")
            )



-- RESPONSE


{-| What the worker sends back.
-}
type alias Response =
    { pages : List Page
    , diagnostics : List Diagnostic
    }


{-| A rendered page. The path is relative to `dist/`, without the base path.
-}
type alias Page =
    { path : String
    , html : String
    }


{-| A problem to show the user, with the optional context that locates it.
-}
type alias Diagnostic =
    { severity : Severity
    , title : String
    , message : String
    , sourcePath : Maybe String
    , span : Maybe Span
    , hint : Maybe String
    }


{-| Errors fail the build; warnings do not.
-}
type Severity
    = Error
    | Warning


{-| The response as the host decodes it. Missing optional fields are left out
rather than sent as `null`.
-}
encodeResponse : Response -> Encode.Value
encodeResponse response =
    Encode.object
        [ ( "pages", Encode.list encodePage response.pages )
        , ( "diagnostics", Encode.list encodeDiagnostic response.diagnostics )
        ]


encodePage : Page -> Encode.Value
encodePage page =
    Encode.object
        [ ( "path", Encode.string page.path )
        , ( "html", Encode.string page.html )
        ]


encodeDiagnostic : Diagnostic -> Encode.Value
encodeDiagnostic diagnostic =
    Encode.object
        ([ ( "severity", encodeSeverity diagnostic.severity )
         , ( "title", Encode.string diagnostic.title )
         , ( "message", Encode.string diagnostic.message )
         ]
            ++ List.filterMap identity
                [ Maybe.map (\path -> ( "sourcePath", Encode.string path )) diagnostic.sourcePath
                , Maybe.map (\span -> ( "span", encodeSpan span )) diagnostic.span
                , Maybe.map (\hint -> ( "hint", Encode.string hint )) diagnostic.hint
                ]
        )


encodeSeverity : Severity -> Encode.Value
encodeSeverity severity =
    case severity of
        Error ->
            Encode.string "error"

        Warning ->
            Encode.string "warning"


encodeSpan : Span -> Encode.Value
encodeSpan span =
    Encode.object
        [ ( "start", encodePosition span.start )
        , ( "end", encodePosition span.end )
        ]


encodePosition : Position -> Encode.Value
encodePosition position =
    Encode.object
        [ ( "line", Encode.int position.line )
        , ( "column", Encode.int position.column )
        ]
