module Docs.Guide exposing (index, page)

{-| The guide's index and its pages.
-}

import Docs.Layout as Layout
import Sheaf
import Sheaf.Document exposing (Document, Neighbour)
import Sheaf.Html exposing (Html, article, h1, li, nav, ol, p, text)
import Sheaf.Html.Attributes exposing (attribute, class)
import Sheaf.Route exposing (Page)


type alias Meta meta =
    { meta | title : String, description : String }


{-| Every page of the guide, in order, with what each one covers.
-}
index : List (Document (Meta meta)) -> Page
index documents =
    Layout.view
        { title = "Guide - Sheaf"
        , description = "How to build and deploy a site with Sheaf."
        , head = []
        , body =
            [ h1 [] [ text "Guide" ]
            , ol [ class "guide-list" ] (List.map entry documents)
            ]
        }


entry : Document (Meta meta) -> Html
entry document =
    li []
        [ p [] [ Sheaf.link document.ref [ text document.meta.title ] ]
        , p [] [ text document.meta.description ]
        ]


{-| One page of the guide, with links to the pages before and after it.
-}
page : Document (Meta meta) -> Page
page document =
    Layout.view
        { title = document.meta.title ++ " - Sheaf"
        , description = document.meta.description
        , head = []
        , body =
            [ article []
                (h1 [] [ text document.meta.title ] :: document.body)
            , nav [ attribute "aria-label" "Pages of the guide" ]
                (List.filterMap identity
                    [ Maybe.map (neighbour "Previous") document.previous
                    , Maybe.map (neighbour "Next") document.next
                    ]
                )
            ]
        }


neighbour : String -> Neighbour (Meta meta) -> Html
neighbour direction other =
    p []
        [ text (direction ++ ": ")
        , Sheaf.link other.ref [ text other.meta.title ]
        ]
