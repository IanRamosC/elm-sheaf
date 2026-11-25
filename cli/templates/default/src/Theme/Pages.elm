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
import Sheaf.Document exposing (Document)
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


{-| A post, at `/posts/<slug>/`.
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
                    :: document.body
                )
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
        heading : String
        heading =
            if pagination.page == 1 then
                "Latest posts"

            else
                "Posts, page " ++ String.fromInt pagination.page ++ " of " ++ String.fromInt pagination.pages
    in
    Layout.view site
        { title =
            if pagination.page == 1 then
                site.title

            else
                titled site heading
        , description = site.description
        , head = []
        , body = [ h1 [] [ text heading ], postList items, pages pagination ]
        }


{-| The posts with one tag, at `/tags/<tag>/`.
-}
tag : Sheaf.Metadata -> String -> Listing (Post meta) -> Page
tag site name { items, pagination } =
    Layout.view site
        { title = titled site ("Posts tagged " ++ name)
        , description = "Posts tagged " ++ name ++ " on " ++ site.title ++ "."
        , head = []
        , body = [ h1 [] [ text ("Posts tagged " ++ name) ], postList items, pages pagination ]
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
            , ol [ class "archive" ]
                (List.map (\item -> li [] [ published item, Sheaf.link item.ref [ text item.meta.title ] ]) items)
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


pages : Pagination -> Html
pages pagination =
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
