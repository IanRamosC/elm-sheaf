module RenderFixtures exposing
    ( PostMeta
    , Source
    , bodyAt
    , containerDirective
    , draft
    , error
    , footnoteDefinition
    , footnoteReference
    , headAt
    , heading
    , image
    , imageWith
    , leafDirective
    , link
    , markdownLink
    , metadata
    , page
    , paragraph
    , paths
    , photo
    , post
    , postMeta
    , postPage
    , postRoute
    , posts
    , render
    , renderWithFeeds
    , request
    , requestUnder
    , requestWithSlugs
    , span
    , textNode
    , titles
    )

{-| The site, requests and response readers that the render tests share.
-}

import Json.Encode as Encode exposing (Value)
import Sheaf
import Sheaf.Collection as Collection exposing (Collection)
import Sheaf.Document exposing (Document)
import Sheaf.Feed exposing (Feed)
import Sheaf.Frontmatter as Frontmatter exposing (Frontmatter)
import Sheaf.Html as Html
import Sheaf.Internal.Protocol exposing (Diagnostic, Response, Severity(..), Span)
import Sheaf.Internal.Render as Render
import Sheaf.Route as Route exposing (Page, Route)



-- THE SITE


type alias PostMeta =
    { title : String
    , tags : List String
    }


postMeta : Frontmatter PostMeta
postMeta =
    Frontmatter.succeed PostMeta
        |> Frontmatter.required "title" Frontmatter.string
        |> Frontmatter.withDefault "tags" [] (Frontmatter.list Frontmatter.string)


posts : Collection PostMeta
posts =
    Collection.named "posts" postMeta


postPage : Document PostMeta -> Page
postPage document =
    { title = document.meta.title
    , head = []
    , body = [ Html.article [] (Html.h1 [] [ Html.text document.meta.title ] :: document.body) ]
    }


postRoute : Route
postRoute =
    Route.eachItem "/posts/:slug/" posts postPage


page : List Html.Html -> Page
page body =
    { title = "Home", head = [], body = body }


render : List Route -> Value -> Response
render routes =
    renderWithFeeds routes []


renderWithFeeds : List Route -> List Feed -> Value -> Response
renderWithFeeds routes feeds =
    Render.render (Sheaf.site { metadata = metadata, routes = routes, feeds = feeds, components = [] })


metadata : Sheaf.Metadata
metadata =
    { title = "Example"
    , description = "A site."
    , author = { name = "Ada", email = Just "ada@example.com" }
    , language = "en"
    }



-- THE REQUEST


type alias Source =
    { collection : String
    , slug : String
    , date : Maybe String
    , updated : Maybe String
    , excluded : Bool
    , frontmatter : List ( String, Value )
    , positions : List ( String, Span )
    , aliases : List String
    , image : Maybe Value
    , body : List Value
    }


post : String -> Source
post slug =
    { collection = "posts"
    , slug = slug
    , date = Nothing
    , updated = Nothing
    , excluded = False
    , frontmatter = [ ( "title", Encode.string slug ) ]
    , positions = []
    , aliases = []
    , image = Nothing
    , body = [ paragraph [ textNode "Hi" ] ]
    }


draft : String -> Source
draft slug =
    let
        published : Source
        published =
            post slug
    in
    { published | excluded = True }


{-| A request for the site at `https://example.com/blog/`.
-}
request : List String -> List Source -> Value
request =
    requestUnder "/blog/"


{-| A request for the site at `https://example.com` and `basePath`.
-}
requestUnder : String -> List String -> List Source -> Value
requestUnder basePath =
    requestWith { basePath = basePath, slugs = [] }


{-| A request for the site at `https://example.com/blog/`, with the host's
table of group slugs: each value, its slug and its folded form.
-}
requestWithSlugs : List ( String, String, String ) -> List String -> List Source -> Value
requestWithSlugs slugs =
    requestWith { basePath = "/blog/", slugs = slugs }


requestWith : { basePath : String, slugs : List ( String, String, String ) } -> List String -> List Source -> Value
requestWith { basePath, slugs } collections sources =
    Encode.object
        [ ( "protocolVersion", Encode.int 4 )
        , ( "build"
          , Encode.object
                [ ( "origin", Encode.string "https://example.com" )
                , ( "basePath", Encode.string basePath )
                , ( "mode", Encode.string "production" )
                ]
          )
        , ( "slugs"
          , Encode.list
                (\( value, slug, folded ) ->
                    Encode.object
                        [ ( "value", Encode.string value )
                        , ( "slug", Encode.string slug )
                        , ( "folded", Encode.string folded )
                        ]
                )
                slugs
          )
        , ( "collections", Encode.list Encode.string collections )
        , ( "documents", Encode.list encodeSource sources )
        ]


encodeSource : Source -> Value
encodeSource source =
    Encode.object
        ([ ( "id", Encode.string (source.collection ++ "/" ++ source.slug) )
         , ( "collection", Encode.string source.collection )
         , ( "sourcePath", Encode.string (sourcePathOf source) )
         , ( "slug", Encode.string source.slug )
         , ( "date", encodeDate source.date )
         , ( "updated", encodeDate source.updated )
         , ( "draft", Encode.bool source.excluded )
         , ( "excluded", Encode.bool source.excluded )
         , ( "frontmatter", Encode.object source.frontmatter )
         , ( "frontmatterPositions", Encode.list (\( path, at ) -> Encode.object [ ( "path", Encode.string path ), ( "value", encodeSpan at ) ]) source.positions )
         , ( "aliases", Encode.list Encode.string source.aliases )
         , ( "tree", markdownNode "root" [ ( "children", Encode.list identity source.body ) ] )
         ]
            ++ optional "image" source.image
        )


optional : String -> Maybe Value -> List ( String, Value )
optional name =
    Maybe.map (\value -> [ ( name, value ) ]) >> Maybe.withDefault []


encodeDate : Maybe String -> Value
encodeDate date =
    date
        |> Maybe.map (\isoDate -> Encode.object [ ( "posixMillis", Encode.int (midnightUtc isoDate) ), ( "isoDate", Encode.string isoDate ) ])
        |> Maybe.withDefault Encode.null


{-| The instant of `YYYY-MM-DD` at midnight UTC, so that dated sources sort
as their dates do. A date that is not one gives 0, for the decoder to reject.
-}
midnightUtc : String -> Int
midnightUtc isoDate =
    case List.map String.toInt (String.split "-" isoDate) of
        [ Just year, Just month, Just day ] ->
            daysSinceEpoch year month day * 86400000

        _ ->
            0


{-| Howard Hinnant's `days_from_civil`.
-}
daysSinceEpoch : Int -> Int -> Int -> Int
daysSinceEpoch year month day =
    let
        shiftedYear : Int
        shiftedYear =
            if month <= 2 then
                year - 1

            else
                year

        era : Int
        era =
            shiftedYear // 400

        yearOfEra : Int
        yearOfEra =
            shiftedYear - era * 400

        dayOfYear : Int
        dayOfYear =
            (153 * modBy 12 (month + 9) + 2) // 5 + day - 1

        dayOfEra : Int
        dayOfEra =
            yearOfEra * 365 + yearOfEra // 4 - yearOfEra // 100 + dayOfYear
    in
    era * 146097 + dayOfEra - 719468


sourcePathOf : Source -> String
sourcePathOf source =
    "content/" ++ source.collection ++ "/" ++ source.slug ++ ".md"


span : Int -> Int -> Int -> Span
span line from to =
    { start = { line = line, column = from }, end = { line = line, column = to } }


encodeSpan : Span -> Value
encodeSpan at =
    let
        position : { line : Int, column : Int } -> Value
        position { line, column } =
            Encode.object [ ( "line", Encode.int line ), ( "column", Encode.int column ) ]
    in
    Encode.object [ ( "start", position at.start ), ( "end", position at.end ) ]


markdownNode : String -> List ( String, Value ) -> Value
markdownNode type_ fields =
    Encode.object (( "type", Encode.string type_ ) :: ( "position", encodeSpan (span 1 1 2) ) :: fields)


paragraph : List Value -> Value
paragraph children =
    markdownNode "paragraph" [ ( "children", Encode.list identity children ) ]


{-| A heading of `depth` with the id the host gave it.
-}
heading : Int -> String -> List Value -> Value
heading depth id children =
    markdownNode "heading" [ ( "depth", Encode.int depth ), ( "id", Encode.string id ), ( "children", Encode.list identity children ) ]


textNode : String -> Value
textNode value =
    markdownNode "text" [ ( "value", Encode.string value ) ]


{-| A Markdown link to the document `id`, written at `at`.
-}
markdownLink : String -> Span -> Value
markdownLink id at =
    case String.split "/" id of
        [ collection, slug ] ->
            Encode.object
                [ ( "type", Encode.string "sheafLink" )
                , ( "position", encodeSpan at )
                , ( "collection", Encode.string collection )
                , ( "slug", Encode.string slug )
                , ( "children", Encode.list identity [ textNode "link" ] )
                ]

        _ ->
            Encode.null


{-| A plain Markdown link to `url`.
-}
link : String -> Value
link url =
    markdownNode "link" [ ( "url", Encode.string url ), ( "children", Encode.list identity [ textNode "link" ] ) ]


{-| A Markdown image of `url` that is not in the site, as a remote one is.
-}
image : String -> Value
image url =
    imageWith { url = url, alt = "", title = Nothing, local = Nothing }


{-| A Markdown image, with what the host found for a local one.
-}
imageWith : { url : String, alt : String, title : Maybe String, local : Maybe Value } -> Value
imageWith fields =
    markdownNode "image"
        ([ ( "url", Encode.string fields.url ), ( "alt", Encode.string fields.alt ) ]
            ++ optional "title" (Maybe.map Encode.string fields.title)
            ++ optional "local" fields.local
        )


{-| What the host sends for a 1200×800 PNG whose hash is `h`, with the
configured widths 480, 960 and 1600 and the format WebP.
-}
photo : Value
photo =
    let
        variant : String -> String -> Value
        variant mediaType extension =
            Encode.object
                [ ( "mediaType", Encode.string mediaType )
                , ( "files"
                  , Encode.list
                        (\width ->
                            Encode.object
                                [ ( "path", Encode.string ("/_sheaf/images/h-" ++ String.fromInt width ++ "." ++ extension) )
                                , ( "width", Encode.int width )
                                ]
                        )
                        [ 480, 960, 1200 ]
                  )
                ]
    in
    Encode.object
        [ ( "src", Encode.string "/_sheaf/images/h-1200.png" )
        , ( "width", Encode.int 1200 )
        , ( "height", Encode.int 800 )
        , ( "variants", Encode.list identity [ variant "image/png" "png", variant "image/webp" "webp" ] )
        ]


{-| A container directive with these attributes and children, written at `at`.
-}
containerDirective : String -> List ( String, String ) -> Span -> List Value -> Value
containerDirective name attributes at children =
    Encode.object
        [ ( "type", Encode.string "containerDirective" )
        , ( "position", encodeSpan at )
        , ( "name", Encode.string name )
        , ( "attributes"
          , Encode.list
                (\( attribute, value ) -> Encode.object [ ( "name", Encode.string attribute ), ( "value", Encode.string value ) ])
                attributes
          )
        , ( "children", Encode.list identity children )
        ]


{-| A leaf directive without attributes, written at `at`.
-}
leafDirective : String -> Span -> Value
leafDirective name at =
    Encode.object
        [ ( "type", Encode.string "leafDirective" )
        , ( "position", encodeSpan at )
        , ( "name", Encode.string name )
        , ( "attributes", Encode.list identity [] )
        ]


footnoteReference : String -> Value
footnoteReference identifier =
    markdownNode "footnoteReference" [ ( "identifier", Encode.string identifier ) ]


footnoteDefinition : String -> String -> Value
footnoteDefinition identifier note =
    markdownNode "footnoteDefinition" [ ( "identifier", Encode.string identifier ), ( "children", Encode.list identity [ paragraph [ textNode note ] ] ) ]



-- READING THE RESPONSE


paths : Response -> List String
paths response =
    List.map .path response.pages


titles : Response -> List String
titles response =
    List.map .title response.diagnostics


{-| What is between `<body>` and `</body>` on the page at `path`.
-}
bodyAt : String -> Response -> Maybe String
bodyAt =
    between "<body>" "</body>"


{-| What is between `<head>` and `</head>` on the page at `path`.
-}
headAt : String -> Response -> Maybe String
headAt =
    between "<head>" "</head>"


between : String -> String -> String -> Response -> Maybe String
between start end path response =
    response.pages
        |> List.filter (\written -> written.path == path)
        |> List.head
        |> Maybe.andThen
            (\written ->
                case String.split start written.html of
                    [ _, rest ] ->
                        List.head (String.split end rest)

                    _ ->
                        Nothing
            )


error : String -> String -> Diagnostic
error title message =
    { severity = Error
    , title = title
    , message = message
    , sourcePath = Nothing
    , span = Nothing
    , hint = Nothing
    }
