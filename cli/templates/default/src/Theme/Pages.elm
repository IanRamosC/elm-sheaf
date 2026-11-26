module Theme.Pages exposing
    ( Post, Titled
    , post, page, index, tag, tags, archive, notFound
    )

{-| A template for each kind of page the blog has.

The templates ask only for the frontmatter they show, so `Site.elm` can decode
more fields without changing them.

@docs Post, Titled
@docs post, page, index, tag, tags, archive, notFound

-}

import Sheaf
import Sheaf.Blog as Blog
import Sheaf.Date as Date exposing (Date)
import Sheaf.Document exposing (Document, Heading, Neighbour)
import Sheaf.Head as Head
import Sheaf.Html exposing (Html, a, article, h1, h2, header, li, nav, ol, p, span, text, time, ul)
import Sheaf.Html.Attributes exposing (attribute, class, datetime, href, siteHref)
import Sheaf.Image as Image
import Sheaf.Route exposing (Group, Listing, Page, Pagination)
import Theme.Layout as Layout
import Time


{-| The frontmatter of a post, as these templates read it.
-}
type alias Post meta =
    { meta | title : String, summary : Maybe String, tags : List String }


{-| The frontmatter of a page, as these templates read it.
-}
type alias Titled meta =
    { meta | title : String }



-- PAGES


{-| A post, at `/posts/<slug>/`: its contents when it has three or more
sections, and links to the older and newer posts at the end.
-}
post : Sheaf.Metadata -> Document (Post meta) -> Page
post site document =
    Layout.view site
        { title = titled site document.meta.title
        , description = Maybe.withDefault site.description document.meta.summary
        , head = [ preview document ]
        , body =
            [ article [ class "post" ]
                (header []
                    [ h1 [] [ text document.meta.title ]
                    , p [ class "byline" ] (published document :: tagLinks document.meta.tags)
                    ]
                    :: cover document
                    :: contents document.headings
                    :: document.body
                )
            , neighbours document
            ]
        }


{-| A page from `content/pages/`, at `/<slug>/`.
-}
page : Sheaf.Metadata -> Document (Titled meta) -> Page
page site document =
    Layout.view site
        { title = titled site document.meta.title
        , description = site.description
        , head = []
        , body = [ article [] (h1 [] [ text document.meta.title ] :: document.body) ]
        }


{-| The newest posts, at `/`, then `/page/2/` and on.
-}
index : Sheaf.Metadata -> Listing (Post meta) -> Page
index site { items, pagination } =
    let
        ( title, heading ) =
            if pagination.page == 1 then
                ( site.title, "Latest posts" )

            else
                let
                    paged : String
                    paged =
                        "Posts, page " ++ String.fromInt pagination.page ++ " of " ++ String.fromInt pagination.pages
                in
                ( titled site paged, paged )
    in
    Layout.view site
        { title = title
        , description = site.description
        , head = []
        , body = [ h1 [] [ text heading ], postList items, pageLinks pagination ]
        }


{-| The posts with one tag, at `/tags/<tag>/`.
-}
tag : Sheaf.Metadata -> String -> Listing (Post meta) -> Page
tag site name { items, pagination } =
    Layout.view site
        { title = titled site ("Posts tagged " ++ name)
        , description = "Posts tagged " ++ name ++ " on " ++ site.title ++ "."
        , head = []
        , body = [ h1 [] [ text ("Posts tagged " ++ name) ], postList items, pageLinks pagination ]
        }


{-| Every tag, at `/tags/`.
-}
tags : Sheaf.Metadata -> List (Group (Post meta)) -> Page
tags site groups =
    Layout.view site
        { title = titled site "Tags"
        , description = "Every tag on " ++ site.title ++ "."
        , head = []
        , body =
            [ h1 [] [ text "Tags" ]
            , ul [ class "tag-index" ] (List.map tagEntry groups)
            ]
        }


{-| Every post, at `/archive/`.
-}
archive : Sheaf.Metadata -> List (Document (Post meta)) -> Page
archive site items =
    Layout.view site
        { title = titled site "Archive"
        , description = "Every post on " ++ site.title ++ "."
        , head = []
        , body =
            [ h1 [] [ text "Archive" ]
            , ol [ class "archive" ] (List.map archiveEntry items)
            ]
        }


{-| The page shown for any address with no page.
-}
notFound : Sheaf.Metadata -> Page
notFound site =
    Layout.view site
        { title = titled site "Page not found"
        , description = site.description
        , head = []
        , body =
            [ h1 [] [ text "Page not found" ]
            , p [] [ text "Nothing lives at this address. Try the ", a [ siteHref "/" ] [ text "home page" ], text "." ]
            ]
        }



-- PARTS


titled : Sheaf.Metadata -> String -> String
titled site name =
    name ++ " · " ++ site.title


preview : Document (Post meta) -> Head.Tag
preview document =
    Head.openGraph
        { title = document.meta.title
        , description = document.meta.summary
        , image = Maybe.map Image.src document.image
        , kind =
            case document.date of
                Just date ->
                    Head.Article { published = date, modified = document.updated }

                Nothing ->
                    Head.Website
        }


cover : Document meta -> Html
cover document =
    case document.image of
        Just image ->
            -- The cover is at the top of the page, where lazy loading only delays it.
            Image.view [ attribute "loading" "eager" ] image

        Nothing ->
            text ""


{-| A post's h2 and h3 headings, each h3 under the h2 before it, linked to
where they are. A post with fewer than three has none.
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
        nav [ attribute "aria-label" "Contents" ]
            [ p [ class "contents-label" ] [ text "Contents" ]
            , ol [ class "contents" ] (List.map contentsEntry (sectionsOf listed))
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


{-| Links to the posts before and after this one, newer first, as the pages of
posts are.
-}
neighbours : Document (Post meta) -> Html
neighbours document =
    case ( document.next, document.previous ) of
        ( Nothing, Nothing ) ->
            text ""

        ( newer, older ) ->
            nav [ attribute "aria-label" "More posts" ]
                [ ul [ class "neighbours" ]
                    [ neighbourLink "newer" "Newer" newer
                    , neighbourLink "older" "Older" older
                    ]
                ]


neighbourLink : String -> String -> Maybe (Neighbour (Post meta)) -> Html
neighbourLink kind label neighbour =
    case neighbour of
        Just other ->
            li [ class kind ]
                [ span [ class "neighbour-label" ] [ text label ]
                , text " "
                , Sheaf.link other.ref [ text other.meta.title ]
                ]

        Nothing ->
            text ""


postList : List (Document (Post meta)) -> Html
postList items =
    if List.isEmpty items then
        p [] [ text "No posts yet." ]

    else
        ol [ class "post-list" ] (List.map postSummary items)


postSummary : Document (Post meta) -> Html
postSummary item =
    li []
        [ h2 [] [ Sheaf.link item.ref [ text item.meta.title ] ]
        , published item
        , case item.meta.summary of
            Just summary ->
                p [] [ text summary ]

            Nothing ->
                text ""
        ]


archiveEntry : Document (Post meta) -> Html
archiveEntry item =
    li [] [ published item, Sheaf.link item.ref [ text item.meta.title ] ]


tagLinks : List String -> List Html
tagLinks names =
    List.map (\name -> span [ class "tag" ] [ Blog.tagLink name [ text name ] ]) names


tagEntry : Group (Post meta) -> Html
tagEntry group =
    li []
        [ Blog.tagLink group.name [ text group.name ]
        , text (" (" ++ String.fromInt (List.length group.items) ++ ")")
        ]


published : Document meta -> Html
published document =
    case document.date of
        Just date ->
            time [ datetime (Date.toIsoDate date) ] [ text (longDate date) ]

        Nothing ->
            text ""


{-| Such as "2 January 2026".
-}
longDate : Date -> String
longDate date =
    String.fromInt (Date.day date) ++ " " ++ monthName (Date.month date) ++ " " ++ String.fromInt (Date.year date)


monthName : Time.Month -> String
monthName month =
    case month of
        Time.Jan ->
            "January"

        Time.Feb ->
            "February"

        Time.Mar ->
            "March"

        Time.Apr ->
            "April"

        Time.May ->
            "May"

        Time.Jun ->
            "June"

        Time.Jul ->
            "July"

        Time.Aug ->
            "August"

        Time.Sep ->
            "September"

        Time.Oct ->
            "October"

        Time.Nov ->
            "November"

        Time.Dec ->
            "December"


pageLinks : Pagination -> Html
pageLinks pagination =
    if pagination.pages <= 1 then
        text ""

    else
        nav [ class "pagination", attribute "aria-label" "Pages" ]
            [ pageLink "Newer posts" pagination.previous
            , pageLink "Older posts" pagination.next
            ]


pageLink : String -> Maybe String -> Html
pageLink label url =
    case url of
        Just address ->
            a [ href address ] [ text label ]

        Nothing ->
            text ""
