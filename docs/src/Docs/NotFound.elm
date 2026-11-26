module Docs.NotFound exposing (view)

{-| The page shown for an address that has none.
-}

import Docs.Layout as Layout
import Sheaf.Html exposing (a, h1, p, text)
import Sheaf.Html.Attributes exposing (siteHref)
import Sheaf.Route exposing (Page)


view : Page
view =
    Layout.view
        { title = "Page not found - Sheaf"
        , description = "Nothing lives at this address."
        , head = []
        , body =
            [ h1 [] [ text "Page not found" ]
            , p []
                [ text "Nothing lives at this address. Try the "
                , a [ siteHref "/guide/" ] [ text "guide" ]
                , text "."
                ]
            ]
        }
