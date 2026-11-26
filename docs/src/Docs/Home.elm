module Docs.Home exposing (view)

{-| The landing page, written in `content/pages/index.md`.
-}

import Docs.Layout as Layout
import Sheaf.Document exposing (Document)
import Sheaf.Html exposing (Html, a, h1, img, p, text)
import Sheaf.Html.Attributes exposing (alt, class, height, siteHref, siteSrc, width)
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
                        :: afterPitch screenshots landing.body
                        ++ [ p [ class "call-to-action" ] [ a [ siteHref "/guide/" ] [ text "Read the guide" ] ] ]
                }

        [] ->
            Layout.view
                { title = "Sheaf"
                , description = ""
                , head = []
                , body = [ h1 [] [ text "Sheaf" ] ]
                }


{-| Puts `html` after the first paragraph of the page, which says what Sheaf
is.
-}
afterPitch : Html -> List Html -> List Html
afterPitch html body =
    case body of
        pitch :: rest ->
            pitch :: html :: rest

        [] ->
            [ html ]


{-| The starter's home page in the reader's colour scheme. The stylesheet
shows one screenshot and hides the other.
-}
screenshots : Html
screenshots =
    p [ class "screenshots" ]
        [ screenshot "light"
        , screenshot "dark"
        ]


screenshot : String -> Html
screenshot scheme =
    img
        [ class ("screenshot-" ++ scheme)
        , siteSrc ("/images/home-" ++ scheme ++ ".png")
        , alt "The home page of the starter blog that sheaf init creates"
        , width 1280
        , height 480
        ]
        []
