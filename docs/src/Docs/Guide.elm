module Docs.Guide exposing (index, page)

{-| The guide's index and its pages.
-}

import Docs.Layout as Layout
import Sheaf
import Sheaf.Document exposing (Document, Heading, Neighbour)
import Sheaf.Html exposing (Attribute, Html, a, article, div, h1, header, li, nav, node, ol, p, span, text, ul)
import Sheaf.Html.Attributes exposing (attribute, class, href, rel, siteHref)
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


{-| One page of the guide, given every page of it for the sidebar: its
contents when it has three or more sections, and links to the pages before
and after it.
-}
page : List (Neighbour (Meta meta)) -> Document (Meta meta) -> Page
page guide document =
    Layout.withSidebar (sidebar guide document)
        { title = document.meta.title ++ " - Sheaf"
        , description = document.meta.description
        , head = []
        , body =
            [ article [ class "guide-page" ]
                [ header [ class "guide-page-title" ] [ h1 [] [ text document.meta.title ] ]
                , contents document.headings
                , div [ class "guide-page-body" ] (document.body ++ [ neighbours document ])
                ]
            ]
        }


{-| The address of a guide page, as `Site.elm` routes it. A plain path, rather
than `Sheaf.link`, lets the links carry `aria-current` and `rel`.
-}
pathOf : Neighbour meta -> String
pathOf other =
    "/guide/" ++ other.slug ++ "/"



-- SIDEBAR


{-| Every page of the guide, with this one marked. On narrow screens it folds
into a disclosure.
-}
sidebar : List (Neighbour (Meta meta)) -> Document (Meta meta) -> Html
sidebar guide document =
    nav [ class "sidebar", attribute "aria-label" "Guide" ]
        [ node "details"
            []
            [ node "summary" [] [ text "Pages of the guide" ]
            , ol [] (List.map (sidebarEntry document.slug) guide)
            ]
        ]


sidebarEntry : String -> Neighbour (Meta meta) -> Html
sidebarEntry currentSlug other =
    let
        current : List Attribute
        current =
            if other.slug == currentSlug then
                [ attribute "aria-current" "page" ]

            else
                []
    in
    li [] [ a (siteHref (pathOf other) :: current) [ text other.meta.title ] ]



-- CONTENTS


{-| A page's h2 and h3 headings, each h3 under the h2 before it, linked to
where they are. A page with fewer than three has none.
-}
contents : List Heading -> Html
contents headings =
    let
        listed : List Heading
        listed =
            List.filter (\heading -> (heading.depth == 2 || heading.depth == 3) && heading.id /= "") headings
    in
    if List.length listed < 3 then
        text ""

    else
        nav [ class "contents", attribute "aria-label" "On this page" ]
            [ p [ class "contents-label" ] [ text "On this page" ]
            , ol [] (List.map contentsEntry (sectionsOf listed))
            ]


type alias Section =
    { heading : Heading
    , subsections : List Heading
    }


{-| Each h2 with the h3s after it. An h3 before the first h2 is a section of
its own.
-}
sectionsOf : List Heading -> List Section
sectionsOf headings =
    let
        step : Heading -> ( List Heading, List Section ) -> ( List Heading, List Section )
        step heading ( subsections, sections ) =
            if heading.depth == 2 then
                ( [], { heading = heading, subsections = subsections } :: sections )

            else
                ( heading :: subsections, sections )

        ( leading, grouped ) =
            List.foldr step ( [], [] ) headings
    in
    List.map (\heading -> { heading = heading, subsections = [] }) leading ++ grouped


contentsEntry : Section -> Html
contentsEntry section =
    if List.isEmpty section.subsections then
        li [] [ headingLink section.heading ]

    else
        li []
            [ headingLink section.heading
            , ol [] (List.map (\subsection -> li [] [ headingLink subsection ]) section.subsections)
            ]


headingLink : Heading -> Html
headingLink heading =
    a [ href ("#" ++ heading.id) ] [ text heading.text ]



-- NEIGHBOURS


neighbours : Document (Meta meta) -> Html
neighbours document =
    case ( document.previous, document.next ) of
        ( Nothing, Nothing ) ->
            text ""

        ( previous, next ) ->
            nav [ attribute "aria-label" "Previous and next pages" ]
                [ ul [ class "neighbours" ]
                    [ neighbourLink "prev" "Previous" previous
                    , neighbourLink "next" "Next" next
                    ]
                ]


neighbourLink : String -> String -> Maybe (Neighbour (Meta meta)) -> Html
neighbourLink relation label neighbour =
    case neighbour of
        Just other ->
            li [ class relation ]
                [ a [ siteHref (pathOf other), rel relation ]
                    [ span [ class "neighbour-label" ] [ text label ]
                    , text " "
                    , span [ class "neighbour-title" ] [ text other.meta.title ]
                    ]
                ]

        Nothing ->
            text ""
