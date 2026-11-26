module Docs.Home exposing (view)

{-| The landing page, written in `content/pages/index.md`.
-}

import Docs.Layout as Layout
import Sheaf.Document exposing (Document)
import Sheaf.Html exposing (a, h1, p, text)
import Sheaf.Html.Attributes exposing (class, siteHref)
import Sheaf.Route exposing (Page)


view : List (Document { meta | title : String, description : String }) -> Page
view documents =
    case List.filter (\document -> document.slug == "index") documents of
        landing :: _ ->
            Layout.view
                { title = landing.meta.title
                , description = landing.meta.description
                , head = []
                , body =
                    h1 [] [ text landing.meta.title ]
                        :: landing.body
                        ++ [ p [ class "call-to-action" ] [ a [ siteHref "/guide/" ] [ text "Read the guide" ] ] ]
                }

        [] ->
            Layout.view
                { title = "Sheaf"
                , description = ""
                , head = []
                , body = [ h1 [] [ text "Sheaf" ] ]
                }
