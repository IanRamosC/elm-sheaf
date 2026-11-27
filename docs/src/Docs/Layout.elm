module Docs.Layout exposing (view, withSidebar)

{-| The frame around every page: the skip link, the header with the site's
navigation, the main content and the footer.
-}

import Sheaf.Head as Head
import Sheaf.Html exposing (Html, a, div, footer, header, li, main_, nav, p, text, ul)
import Sheaf.Html.Attributes exposing (attribute, class, href, id, siteHref, title)
import Sheaf.Route exposing (Page)
import Sheaf.Svg exposing (path, rect, svg)
import Sheaf.Svg.Attributes as SvgA


type alias Content =
    { title : String
    , description : String
    , head : List Head.Tag
    , body : List Html
    }


{-| A page with this title, description, extra `<head>` tags and content.
The title is the whole `<title>`, so it should name the site too.
-}
view : Content -> Page
view content =
    frame content (main_ [ id "main" ] content.body)


{-| Like [`view`](#view), with a sidebar beside the content on wide screens
and above it on narrow ones.
-}
withSidebar : Html -> Content -> Page
withSidebar sidebar content =
    frame content
        (div [ class "with-sidebar" ]
            [ sidebar
            , main_ [ id "main" ] content.body
            ]
        )


frame : Content -> Html -> Page
frame content main =
    { title = content.title
    , head =
        Head.canonical
            :: Head.description content.description
            :: Head.openGraph
                { title = content.title
                , description = Just content.description
                , image = Nothing
                , kind = Head.Website
                }
            :: Head.stylesheet "/style.css"
            :: Head.icon { path = "/favicon.svg", mediaType = "image/svg+xml" }
            :: content.head
    , body =
        [ a [ class "skip-link", href "#main" ] [ text "Skip to content" ]
        , siteHeader
        , main
        , footer [ class "site-footer" ]
            [ p []
                [ text "Sheaf is open source under the BSD 3-Clause "
                , a [ href "https://github.com/IanRamosC/elm-sheaf/blob/main/LICENSE" ] [ text "licence" ]
                , text "."
                ]
            ]
        ]
    }


siteHeader : Html
siteHeader =
    header [ class "site-header" ]
        [ a [ class "site-title", siteHref "/" ]
            [ svg [ SvgA.viewBox "0 0 64 64", SvgA.width "28", SvgA.height "28", attribute "aria-hidden" "true" ]
                [ rect [ SvgA.x "2", SvgA.y "2", SvgA.width "60", SvgA.height "60", SvgA.rx "14", SvgA.fill "#24599a" ] []
                , path
                    [ SvgA.d "M51 15.5 H28 A8 8 0 0 0 28 31.5 H36 A8 8 0 0 1 36 47.5 H13"
                    , SvgA.fill "none"
                    , SvgA.stroke "#fbfaf7"
                    , SvgA.strokeWidth "10"
                    ]
                    []
                ]
            , text "Sheaf"
            ]
        , nav [ attribute "aria-label" "Site" ]
            [ ul []
                [ li [] [ a [ siteHref "/guide/" ] [ text "Guide" ] ]
                , li []
                    [ a
                        [ href "https://github.com/IanRamosC/elm-sheaf/tree/main/src/Sheaf"
                        , title "The API docs move to package.elm-lang.org with the 1.0.0 release"
                        ]
                        [ text "API" ]
                    ]
                , li [] [ a [ href "https://github.com/IanRamosC/elm-sheaf" ] [ text "GitHub" ] ]
                ]
            ]
        ]
