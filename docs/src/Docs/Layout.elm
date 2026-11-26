module Docs.Layout exposing (view)

{-| The frame around every page: the skip link, the header with the site's
navigation, the main content and the footer.
-}

import Sheaf
import Sheaf.Head as Head
import Sheaf.Html exposing (Html, a, footer, header, li, main_, nav, p, text, ul)
import Sheaf.Html.Attributes exposing (attribute, class, href, id, siteHref, title)
import Sheaf.Route exposing (Page)


{-| A page with this title, description, extra `<head>` tags and content.
The title is the whole `<title>`, so it should name the site too.
-}
view :
    { title : String
    , description : String
    , head : List Head.Tag
    , body : List Html
    }
    -> Page
view page =
    { title = page.title
    , head =
        Head.canonical
            :: Head.description page.description
            :: Head.openGraph
                { title = page.title
                , description = Just page.description
                , image = Nothing
                , kind = Head.Website
                }
            :: page.head
    , body =
        [ a [ class "skip-link", href "#main" ] [ text "Skip to content" ]
        , header [ class "site-header" ]
            [ a [ class "site-title", siteHref "/" ] [ text "Sheaf" ]
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
        , main_ [ id "main" ] page.body
        , footer [ class "site-footer" ]
            [ p [] [ text "Sheaf is open source under the BSD 3-Clause license." ] ]
        ]
    }
