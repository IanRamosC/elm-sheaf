module Sheaf.Internal.Protocol exposing
    ( Request, Build, BuildMode(..), GroupSlug, Document, Date
    , DocumentImage, LocalImage, ImageVariant
    , Span, Position, FieldPosition
    , Node(..), Container, Alignment(..), Highlight, Token
    , requestDecoder
    , Response, Metadata, Page, Feed, FeedItem, SitemapEntry, Diagnostic, Severity(..), encodeResponse
    )

{-| The JSON the host and the Elm worker exchange.

The types mirror `cli/src/elm/protocol.ts` and `cli/src/markdown/tree.ts`, and
`tests/fixtures/protocol/` holds JSON that both sides are tested against, so a
change to one side is a change to the other.

It is not exposed by the package.

@docs Request, Build, BuildMode, GroupSlug, Document, Date
@docs DocumentImage, LocalImage, ImageVariant
@docs Span, Position, FieldPosition
@docs Node, Container, Alignment, Highlight, Token
@docs requestDecoder
@docs Response, Metadata, Page, Feed, FeedItem, SitemapEntry, Diagnostic, Severity, encodeResponse

-}

import Dict exposing (Dict)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Time



-- REQUEST


{-| Everything the host knows about the site.

`collections` names every folder in `content/`, including empty ones, which
have no documents. `slugs` is the host's table of group slugs, by the value
that was slugged. `stylesheets` has the hashed path of each stylesheet in
`static/`, by its path, both relative to the site's root.

-}
type alias Request =
    { build : Build
    , slugs : Dict String GroupSlug
    , stylesheets : Dict String String
    , collections : List String
    , documents : List Document
    }


{-| How this build was invoked. `origin` has no trailing slash, so an
absolute URL is `origin ++ url`, where `url` already has the base path.
-}
type alias Build =
    { origin : String
    , basePath : String
    , mode : BuildMode
    }


{-| `Drafts` builds include drafts and future-dated documents.
-}
type BuildMode
    = Production
    | Drafts


{-| The slug a frontmatter value groups under. `folded` is the value with its
case and accents removed, to tell when two values would share a slug.
-}
type alias GroupSlug =
    { slug : String
    , folded : String
    }


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
    , aliases : List String
    , image : Maybe DocumentImage
    , tree : Node
    }


{-| A document's `image` key. `url` is the value as written; `local` is there
for an image in `content/` or `static/`, and not for an http(s) URL.
-}
type alias DocumentImage =
    { url : String
    , alt : String
    , local : Maybe LocalImage
    }


{-| A local image as published, with paths from the root of the site that do
not have the base path yet.

`src` is the original format at the largest width, and `width` and `height`
are that file's. The first variant is the original format and each other one
a configured format. GIF and SVG files are published unchanged, so they have
no variants.

-}
type alias LocalImage =
    { src : String
    , width : Int
    , height : Int
    , variants : List ImageVariant
    }


{-| One format of an image, at every width it is written in, narrowest first.
-}
type alias ImageVariant =
    { mediaType : String
    , files : List { path : String, width : Int }
    }


{-| A moment, and the calendar date as the author wrote it (`isoDate`, with its
parts), which is not necessarily the day of the moment in UTC.
-}
type alias Date =
    { posix : Time.Posix
    , isoDate : String
    , year : Int
    , month : Time.Month
    , day : Int
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
    5


{-| Decodes the host's request, which must speak this protocol version.
-}
requestDecoder : Decoder Request
requestDecoder =
    Decode.field "protocolVersion" Decode.int
        |> Decode.andThen
            (\version ->
                if version == protocolVersion then
                    Decode.map5 Request
                        (Decode.field "build" buildDecoder)
                        (Decode.field "slugs" slugsDecoder)
                        (Decode.field "stylesheets" stylesheetsDecoder)
                        (Decode.field "collections" (Decode.list Decode.string))
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
        (Decode.field "origin" Decode.string)
        (Decode.field "basePath" Decode.string)
        (Decode.field "mode" buildModeDecoder)


slugsDecoder : Decoder (Dict String GroupSlug)
slugsDecoder =
    Decode.list
        (Decode.map3 (\value slug folded -> ( value, { slug = slug, folded = folded } ))
            (Decode.field "value" Decode.string)
            (Decode.field "slug" Decode.string)
            (Decode.field "folded" Decode.string)
        )
        |> Decode.map Dict.fromList


stylesheetsDecoder : Decoder (Dict String String)
stylesheetsDecoder =
    Decode.list
        (Decode.map2 Tuple.pair
            (Decode.field "path" Decode.string)
            (Decode.field "hashed" Decode.string)
        )
        |> Decode.map Dict.fromList


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
        |> andMap (Decode.field "frontmatterPositions" fieldPositionsDecoder)
        |> andMap (Decode.field "aliases" (Decode.list Decode.string))
        |> andMap (optionalField "image" documentImageDecoder)
        |> andMap (Decode.field "tree" nodeDecoder)


documentImageDecoder : Decoder DocumentImage
documentImageDecoder =
    Decode.map3 DocumentImage
        (Decode.field "url" Decode.string)
        (Decode.field "alt" Decode.string)
        (optionalField "local" localImageDecoder)


localImageDecoder : Decoder LocalImage
localImageDecoder =
    Decode.map4 LocalImage
        (Decode.field "src" Decode.string)
        (Decode.field "width" Decode.int)
        (Decode.field "height" Decode.int)
        (Decode.field "variants"
            (Decode.list
                (Decode.map2 ImageVariant
                    (Decode.field "mediaType" Decode.string)
                    (Decode.field "files"
                        (Decode.list
                            (Decode.map2 (\path width -> { path = path, width = width })
                                (Decode.field "path" Decode.string)
                                (Decode.field "width" Decode.int)
                            )
                        )
                    )
                )
            )
        )


andMap : Decoder a -> Decoder (a -> b) -> Decoder b
andMap =
    Decode.map2 (|>)


dateDecoder : Decoder Date
dateDecoder =
    Decode.map2 Tuple.pair
        (Decode.map Time.millisToPosix (Decode.field "posixMillis" Decode.int))
        (Decode.field "isoDate" Decode.string)
        |> Decode.andThen
            (\( posix, isoDate ) ->
                case parseIsoDate isoDate of
                    Just ( year, month, day ) ->
                        Decode.succeed { posix = posix, isoDate = isoDate, year = year, month = month, day = day }

                    Nothing ->
                        Decode.fail ("`" ++ isoDate ++ "` is not a calendar date written as YYYY-MM-DD")
            )


parseIsoDate : String -> Maybe ( Int, Time.Month, Int )
parseIsoDate isoDate =
    case String.split "-" isoDate of
        [ yearText, monthText, dayText ] ->
            if String.length yearText == 4 && String.length monthText == 2 && String.length dayText == 2 then
                Maybe.map3 (\year monthNumber day -> ( year, monthNumber, day ))
                    (String.toInt yearText)
                    (String.toInt monthText)
                    (String.toInt dayText)
                    |> Maybe.andThen validDate

            else
                Nothing

        _ ->
            Nothing


validDate : ( Int, Int, Int ) -> Maybe ( Int, Time.Month, Int )
validDate ( year, monthNumber, day ) =
    monthFromNumber monthNumber
        |> Maybe.andThen
            (\month ->
                if day >= 1 && day <= daysInMonth year month then
                    Just ( year, month, day )

                else
                    Nothing
            )


monthFromNumber : Int -> Maybe Time.Month
monthFromNumber number =
    List.head (List.drop (number - 1) months)
        |> Maybe.andThen
            (\month ->
                if number >= 1 then
                    Just month

                else
                    Nothing
            )


months : List Time.Month
months =
    [ Time.Jan, Time.Feb, Time.Mar, Time.Apr, Time.May, Time.Jun, Time.Jul, Time.Aug, Time.Sep, Time.Oct, Time.Nov, Time.Dec ]


daysInMonth : Int -> Time.Month -> Int
daysInMonth year month =
    case month of
        Time.Feb ->
            if isLeapYear year then
                29

            else
                28

        Time.Apr ->
            30

        Time.Jun ->
            30

        Time.Sep ->
            30

        Time.Nov ->
            30

        _ ->
            31


isLeapYear : Int -> Bool
isLeapYear year =
    (modBy 4 year == 0 && modBy 100 year /= 0) || modBy 400 year == 0


{-| The host sends a list, not an object keyed by path, because `Decode.dict`
fails on a key named `hasOwnProperty`.
-}
fieldPositionsDecoder : Decoder (Dict String FieldPosition)
fieldPositionsDecoder =
    Decode.list
        (Decode.map3 (\path key value -> ( path, { key = key, value = value } ))
            (Decode.field "path" Decode.string)
            (optionalField "key" spanDecoder)
            (Decode.field "value" spanDecoder)
        )
        |> Decode.map Dict.fromList


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
    | Code { position : Span, lang : Maybe String, value : String, highlight : Highlight }
    | Blockquote Container
    | ListBlock { position : Span, ordered : Bool, start : Maybe Int, spread : Bool, children : List Node }
    | ListItem { position : Span, checked : Maybe Bool, children : List Node }
    | ThematicBreak { position : Span }
    | Break { position : Span }
    | Link { position : Span, url : String, title : Maybe String, children : List Node }
    | SheafLink { position : Span, collection : String, slug : String, fragment : Maybe String, title : Maybe String, children : List Node }
    | Image { position : Span, url : String, alt : String, title : Maybe String, local : Maybe LocalImage }
    | Table { position : Span, align : List (Maybe Alignment), children : List Node }
    | TableRow Container
    | TableCell Container
    | FootnoteDefinition { position : Span, identifier : String, children : List Node }
    | FootnoteReference { position : Span, identifier : String }
    | ContainerDirective { position : Span, name : String, attributes : List ( String, String ), children : List Node }
    | LeafDirective { position : Span, name : String, attributes : List ( String, String ) }


{-| The fields of every node that only holds other nodes.
-}
type alias Container =
    { position : Span, children : List Node }


{-| A code block as Shiki highlighted it: the style of the whole block, and
each line as a list of tokens.
-}
type alias Highlight =
    { style : String, lines : List (List Token) }


{-| A run of code with one style. An empty `style` means Shiki gave it none.
-}
type alias Token =
    { content : String, style : String }


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
            Decode.map4 (\position lang value highlight -> Code { position = position, lang = lang, value = value, highlight = highlight })
                positionField
                (optionalField "lang" Decode.string)
                (Decode.field "value" Decode.string)
                (Decode.field "highlight" highlightDecoder)

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
            Decode.map5 (\position url alt title local -> Image { position = position, url = url, alt = alt, title = title, local = local })
                positionField
                (Decode.field "url" Decode.string)
                (Decode.field "alt" Decode.string)
                (optionalField "title" Decode.string)
                (optionalField "local" localImageDecoder)

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

        "containerDirective" ->
            Decode.map4 (\position name attributes children -> ContainerDirective { position = position, name = name, attributes = attributes, children = children })
                positionField
                (Decode.field "name" Decode.string)
                attributesField
                childrenField

        "leafDirective" ->
            Decode.map3 (\position name attributes -> LeafDirective { position = position, name = name, attributes = attributes })
                positionField
                (Decode.field "name" Decode.string)
                attributesField

        _ ->
            Decode.fail ("Unknown Markdown node type \"" ++ type_ ++ "\"")


positionField : Decoder Span
positionField =
    Decode.field "position" spanDecoder


childrenField : Decoder (List Node)
childrenField =
    Decode.field "children" (Decode.list (Decode.lazy (\_ -> nodeDecoder)))


attributesField : Decoder (List ( String, String ))
attributesField =
    Decode.field "attributes"
        (Decode.list
            (Decode.map2 Tuple.pair
                (Decode.field "name" Decode.string)
                (Decode.field "value" Decode.string)
            )
        )


containerDecoder : Decoder Container
containerDecoder =
    Decode.map2 Container positionField childrenField


highlightDecoder : Decoder Highlight
highlightDecoder =
    Decode.map2 Highlight
        (Decode.field "style" Decode.string)
        (Decode.field "lines"
            (Decode.list
                (Decode.list
                    (Decode.map2 Token
                        (Decode.field "content" Decode.string)
                        (Decode.field "style" Decode.string)
                    )
                )
            )
        )


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


{-| What the worker sends back. `feeds` and `sitemap` are what the host
writes besides the pages.
-}
type alias Response =
    { site : Metadata
    , pages : List Page
    , feeds : List Feed
    , sitemap : List SitemapEntry
    , diagnostics : List Diagnostic
    }


{-| What the site says about itself, for feeds and the sitemap.
-}
type alias Metadata =
    { title : String
    , description : String
    , author : { name : String, email : Maybe String }
    , language : String
    }


{-| A rendered page. The path is relative to `dist/`, without the base path.
A redirect page has `aliasOf`, the source path of the document it redirects
to.
-}
type alias Page =
    { path : String
    , html : String
    , aliasOf : Maybe String
    }


{-| An RSS and an Atom file for the same items, under the channel's `title`.
The paths are relative to `dist/`, without the base path.
-}
type alias Feed =
    { rss : String
    , atom : String
    , title : String
    , items : List FeedItem
    }


{-| One entry of a feed. `url` is absolute.
-}
type alias FeedItem =
    { documentId : String
    , url : String
    , title : String
    , summary : Maybe String
    , html : String
    , date : Time.Posix
    , updated : Time.Posix
    }


{-| A page for search engines to find. `url` is absolute.
-}
type alias SitemapEntry =
    { url : String
    , lastModified : Maybe Time.Posix
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


{-| The response as the host decodes it. Missing fields of a diagnostic are
left out, while the optional fields of the site, feeds and sitemap are sent as
`null`.
-}
encodeResponse : Response -> Encode.Value
encodeResponse response =
    Encode.object
        [ ( "site", encodeMetadata response.site )
        , ( "pages", Encode.list encodePage response.pages )
        , ( "feeds", Encode.list encodeFeed response.feeds )
        , ( "sitemap", Encode.list encodeSitemapEntry response.sitemap )
        , ( "diagnostics", Encode.list encodeDiagnostic response.diagnostics )
        ]


encodeMetadata : Metadata -> Encode.Value
encodeMetadata metadata =
    Encode.object
        [ ( "title", Encode.string metadata.title )
        , ( "description", Encode.string metadata.description )
        , ( "author"
          , Encode.object
                [ ( "name", Encode.string metadata.author.name )
                , ( "email", encodeNullable Encode.string metadata.author.email )
                ]
          )
        , ( "language", Encode.string metadata.language )
        ]


encodeFeed : Feed -> Encode.Value
encodeFeed feed =
    Encode.object
        [ ( "rss", Encode.string feed.rss )
        , ( "atom", Encode.string feed.atom )
        , ( "title", Encode.string feed.title )
        , ( "items", Encode.list encodeFeedItem feed.items )
        ]


encodeFeedItem : FeedItem -> Encode.Value
encodeFeedItem item =
    Encode.object
        [ ( "documentId", Encode.string item.documentId )
        , ( "url", Encode.string item.url )
        , ( "title", Encode.string item.title )
        , ( "summary", encodeNullable Encode.string item.summary )
        , ( "html", Encode.string item.html )
        , ( "date", Encode.int (Time.posixToMillis item.date) )
        , ( "updated", Encode.int (Time.posixToMillis item.updated) )
        ]


encodeSitemapEntry : SitemapEntry -> Encode.Value
encodeSitemapEntry entry =
    Encode.object
        [ ( "url", Encode.string entry.url )
        , ( "lastModified", encodeNullable (Time.posixToMillis >> Encode.int) entry.lastModified )
        ]


encodeNullable : (a -> Encode.Value) -> Maybe a -> Encode.Value
encodeNullable encode maybe =
    maybe |> Maybe.map encode |> Maybe.withDefault Encode.null


encodePage : Page -> Encode.Value
encodePage page =
    Encode.object
        ([ ( "path", Encode.string page.path )
         , ( "html", Encode.string page.html )
         ]
            ++ (page.aliasOf
                    |> Maybe.map (\path -> [ ( "aliasOf", Encode.string path ) ])
                    |> Maybe.withDefault []
               )
        )


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
