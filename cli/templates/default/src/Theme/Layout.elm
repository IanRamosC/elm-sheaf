module Theme.Layout exposing (view)

{-| The frame around every page: the skip link, the header with the site's
navigation, the main content and the footer.
-}

import Content.Pages
import Sheaf
import Sheaf.Head as Head
import Sheaf.Html exposing (Html, a, footer, header, li, main_, nav, p, text, ul)
import Sheaf.Html.Attributes exposing (attribute, class, href, id, siteHref)
import Sheaf.Route exposing (Page)


{-| A page with this title, description, extra `<head>` tags and content.
The title is the whole `<title>`, so it should name the site too.
-}
view :
    Sheaf.Metadata
    ->
        { title : String
        , description : String
        , head : List Head.Tag
        , body : List Html
        }
    -> Page
view site page =
    { title = page.title
    , head =
        Head.canonical
            :: Head.description page.description
            :: Head.stylesheet "/style.css"
            :: Head.icon { path = "/favicon.svg", mediaType = "image/svg+xml" }
            :: page.head
    , body =
        [ a [ class "skip-link", href "#main" ] [ text "Skip to content" ]
        , header [ class "site-header" ]
            [ a [ class "site-title", siteHref "/" ] [ text site.title ]
            , nav [ attribute "aria-label" "Site" ]
                [ ul []
                    [ li [] [ a [ siteHref "/archive/" ] [ text "Archive" ] ]
                    , li [] [ a [ siteHref "/tags/" ] [ text "Tags" ] ]
                    , li [] [ Sheaf.link Content.Pages.about [ text "About" ] ]
                    ]
                ]
            ]
        , main_ [ id "main" ] page.body
        , footer [ class "site-footer" ]
            [ p [] [ text ("Written by " ++ site.author.name ++ ".") ]
            , p []
                [ text "Follow by "
                , a [ siteHref "/feed.xml" ] [ text "RSS" ]
                , text " or "
                , a [ siteHref "/atom.xml" ] [ text "Atom" ]
                , text "."
                ]
            ]
        ]
    }
