module Docs.Layout exposing (view, withSidebar)

{-| The frame around every page: the skip link, the header with the site's
navigation, the main content and the footer.
-}

import Sheaf.Head as Head
import Sheaf.Html exposing (Html, a, div, footer, header, img, li, main_, nav, p, text, ul)
import Sheaf.Html.Attributes exposing (alt, attribute, class, height, href, id, siteHref, siteSrc, title, width)
import Sheaf.Route exposing (Page)


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
            [ img [ siteSrc "/favicon.svg", alt "", width 28, height 28 ] []
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
