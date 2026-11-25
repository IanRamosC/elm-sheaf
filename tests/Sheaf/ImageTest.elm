module Sheaf.ImageTest exposing (suite)

import Expect
import Json.Encode as Encode exposing (Value)
import RenderFixtures exposing (PostMeta, Source, bodyAt, imageWith, page, paragraph, photo, post, posts, render, request)
import Sheaf.Document exposing (Document)
import Sheaf.Html as Html
import Sheaf.Html.Attributes exposing (attribute, class)
import Sheaf.Image as Image
import Sheaf.Route as Route
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Sheaf.Image"
        [ markdownTests
        , coverTests
        ]



-- MARKDOWN IMAGES


bodyOf : Value -> Maybe String
bodyOf node =
    request [ "posts" ] [ withBody [ paragraph [ node ] ] (post "a") ]
        |> render [ Route.eachItem "/posts/:slug/" posts (\document -> page document.body) ]
        |> bodyAt "posts/a/index.html"


withBody : List Value -> Source -> Source
withBody body source =
    { source | body = body }


photoSrcset : String -> String
photoSrcset extension =
    [ 480, 960, 1200 ]
        |> List.map (\width -> "/blog/_sheaf/images/h-" ++ String.fromInt width ++ "." ++ extension ++ " " ++ String.fromInt width ++ "w")
        |> String.join ", "


photoHtml : String -> String
photoHtml extraAttributes =
    String.concat
        [ "<picture>"
        , "<source type=\"image/webp\" srcset=\"" ++ photoSrcset "webp" ++ "\" sizes=\"(min-width: 1200px) 1200px, 100vw\">"
        , "<img src=\"/blog/_sheaf/images/h-1200.png\" srcset=\"" ++ photoSrcset "png" ++ "\" sizes=\"(min-width: 1200px) 1200px, 100vw\""
        , " width=\"1200\" height=\"800\" alt=\"A photo\" loading=\"lazy\" decoding=\"async\"" ++ extraAttributes ++ ">"
        , "</picture>"
        ]


markdownTests : Test
markdownTests =
    describe "images in Markdown"
        [ test "a local image is a picture with a source for each other format" <|
            \_ ->
                bodyOf (imageWith { url = "photo.png", alt = "A photo", title = Nothing, local = Just photo })
                    |> Expect.equal (Just ("<p>" ++ photoHtml "" ++ "</p>"))
        , test "the title goes on the img" <|
            \_ ->
                bodyOf (imageWith { url = "photo.png", alt = "A photo", title = Just "Mine", local = Just photo })
                    |> Expect.equal (Just ("<p>" ++ photoHtml " title=\"Mine\"" ++ "</p>"))
        , test "a GIF, which has no variants, is an img with its size" <|
            \_ ->
                bodyOf
                    (imageWith
                        { url = "spin.gif"
                        , alt = "Spinning"
                        , title = Nothing
                        , local =
                            Just
                                (Encode.object
                                    [ ( "src", Encode.string "/_sheaf/images/g-300.gif" )
                                    , ( "width", Encode.int 300 )
                                    , ( "height", Encode.int 200 )
                                    , ( "variants", Encode.list identity [] )
                                    ]
                                )
                        }
                    )
                    |> Expect.equal (Just "<p><img src=\"/blog/_sheaf/images/g-300.gif\" width=\"300\" height=\"200\" alt=\"Spinning\" loading=\"lazy\" decoding=\"async\"></p>")
        , test "a remote image keeps its URL and has no size" <|
            \_ ->
                bodyOf (imageWith { url = "https://example.org/a.png", alt = "A", title = Nothing, local = Nothing })
                    |> Expect.equal (Just "<p><img src=\"https://example.org/a.png\" alt=\"A\" loading=\"lazy\" decoding=\"async\"></p>")
        ]



-- COVER IMAGES


cover : Maybe Value -> Value
cover local =
    Encode.object
        (( "url", Encode.string "photo.png" )
            :: ( "alt", Encode.string "A photo" )
            :: (case local of
                    Just value ->
                        [ ( "local", value ) ]

                    Nothing ->
                        []
               )
        )


withCover : Value -> Source -> Source
withCover image source =
    { source | image = Just image }


renderCover : (Document PostMeta -> List Html.Html) -> Source -> Maybe String
renderCover template source =
    request [ "posts" ] [ source ]
        |> render [ Route.eachItem "/posts/:slug/" posts (template >> page) ]
        |> bodyAt "posts/a/index.html"


coverTests : Test
coverTests =
    describe "cover images"
        [ test "a document with an image has it" <|
            \_ ->
                post "a"
                    |> withCover (cover (Just photo))
                    |> renderCover (\document -> List.filterMap (Maybe.map (Image.view [ class "cover" ])) [ document.image ])
                    |> Expect.equal (Just (photoHtml " class=\"cover\""))
        , test "a document without one has nothing" <|
            \_ ->
                post "a"
                    |> renderCover (\document -> List.filterMap (Maybe.map facts) [ document.image ])
                    |> Expect.equal (Just "")
        , test "an attribute of the template replaces the one Sheaf gives" <|
            \_ ->
                post "a"
                    |> withCover (cover (Just photo))
                    |> renderCover (\document -> List.filterMap (Maybe.map (Image.view [ attribute "loading" "eager" ])) [ document.image ])
                    |> Maybe.map (String.contains "decoding=\"async\" loading=\"eager\">")
                    |> Expect.equal (Just True)
        , test "a local image's source, size and alt" <|
            \_ ->
                post "a"
                    |> withCover (cover (Just photo))
                    |> renderCover (\document -> List.filterMap (Maybe.map facts) [ document.image ])
                    |> Expect.equal (Just "/_sheaf/images/h-1200.png 1200 800 A photo")
        , test "a remote image has its URL and no size" <|
            \_ ->
                post "a"
                    |> withCover
                        (Encode.object
                            [ ( "url", Encode.string "https://example.org/a.png" ), ( "alt", Encode.string "" ) ]
                        )
                    |> renderCover (\document -> List.filterMap (Maybe.map facts) [ document.image ])
                    |> Expect.equal (Just "https://example.org/a.png ? ? ")
        ]


facts : Image.Image -> Html.Html
facts image =
    Html.text
        (String.join " "
            [ Image.src image
            , Maybe.withDefault "?" (Maybe.map String.fromInt (Image.width image))
            , Maybe.withDefault "?" (Maybe.map String.fromInt (Image.height image))
            , Image.alt image
            ]
        )
