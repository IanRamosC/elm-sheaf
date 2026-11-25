module Sheaf.Internal.Image exposing (Image, fromProtocol, view, src, width, height, alt)

{-| An image as the host resolved it, and its markup, which Markdown images
and [`Sheaf.Image.view`](Sheaf-Image#view) share.

It is not exposed by the package so that only the host can make an `Image`.

@docs Image, fromProtocol, view, src, width, height, alt

-}

import Sheaf.Internal.Html as Html exposing (Attribute, Html)
import Sheaf.Internal.Protocol exposing (ImageVariant, LocalImage)


{-| A local image, published by Sheaf, or a remote one, which keeps its URL.
-}
type Image
    = Local String LocalImage
    | Remote String String


{-| The image of a Markdown node or of a document's `image` key.
-}
fromProtocol : { a | url : String, alt : String, local : Maybe LocalImage } -> Image
fromProtocol image =
    case image.local of
        Just local ->
            Local image.alt local

        Nothing ->
            Remote image.alt image.url


{-| A `picture` with a `source` for each format other than the original, or a
plain `img` for an image with no variants. `attributes` go on the `img`, and
one of them replaces Sheaf's attribute of the same name.
-}
view : List Attribute -> Image -> Html
view attributes image =
    case image of
        Local altText local ->
            case local.variants of
                original :: others ->
                    Html.node "picture"
                        []
                        (List.map (source (sizes local)) others
                            ++ [ img attributes
                                    [ Html.sitePathAttribute "src" local.src
                                    , srcset original
                                    , sizes local
                                    , size "width" local.width
                                    , size "height" local.height
                                    , Html.attribute "alt" altText
                                    ]
                               ]
                        )

                [] ->
                    img attributes
                        [ Html.sitePathAttribute "src" local.src
                        , size "width" local.width
                        , size "height" local.height
                        , Html.attribute "alt" altText
                        ]

        Remote altText url ->
            img attributes [ Html.attribute "src" url, Html.attribute "alt" altText ]


img : List Attribute -> List Attribute -> Html
img attributes own =
    let
        given : List String
        given =
            List.map Html.attributeName attributes
    in
    Html.node "img"
        (List.filter (\attr -> not (List.member (Html.attributeName attr) given))
            (own ++ [ Html.attribute "loading" "lazy", Html.attribute "decoding" "async" ])
            ++ attributes
        )
        []


source : Attribute -> ImageVariant -> Html
source sizesAttribute variant =
    Html.node "source" [ Html.attribute "type" variant.mediaType, srcset variant, sizesAttribute ] []


srcset : ImageVariant -> Attribute
srcset variant =
    Html.siteSrcset variant.files


{-| The image is shown at the width of the page, up to its largest file.
-}
sizes : LocalImage -> Attribute
sizes local =
    let
        pixels : String
        pixels =
            String.fromInt local.width ++ "px"
    in
    Html.attribute "sizes" ("(min-width: " ++ pixels ++ ") " ++ pixels ++ ", 100vw")


size : String -> Int -> Attribute
size name pixels =
    Html.attribute name (String.fromInt pixels)


{-| The URL of the image: for a local one, its largest file in the original
format, as a path from the root of the site without the base path.
-}
src : Image -> String
src image =
    case image of
        Local _ local ->
            local.src

        Remote _ url ->
            url


{-| The width in pixels of the file [`src`](#src) points to, if Sheaf
published it.
-}
width : Image -> Maybe Int
width image =
    case image of
        Local _ local ->
            Just local.width

        Remote _ _ ->
            Nothing


{-| The height in pixels of the file [`src`](#src) points to, if Sheaf
published it.
-}
height : Image -> Maybe Int
height image =
    case image of
        Local _ local ->
            Just local.height

        Remote _ _ ->
            Nothing


{-| The text that describes the image.
-}
alt : Image -> String
alt image =
    case image of
        Local altText _ ->
            altText

        Remote altText _ ->
            altText
