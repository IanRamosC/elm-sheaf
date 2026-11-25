module Site exposing (site)

import Content.Pages
import Sheaf
import Sheaf.Blog as Blog
import Sheaf.Component as Component exposing (Component)
import Sheaf.Date as Date
import Sheaf.Document exposing (Document)
import Sheaf.Frontmatter as Frontmatter exposing (Frontmatter)
import Sheaf.Head as Head
import Sheaf.Html exposing (Html, a, article, aside, footer, h1, h2, header, li, main_, nav, p, text, time, ul)
import Sheaf.Html.Attributes exposing (attribute, class, datetime, href, siteHref)
import Sheaf.Image as Image
import Sheaf.Route exposing (Group, Listing, Page, Pagination)


type alias PostMeta =
    { title : String
    , summary : Maybe String
    , tags : List String
    }


type alias PageMeta =
    { title : String }


postMeta : Frontmatter PostMeta
postMeta =
    Frontmatter.succeed PostMeta
        |> Frontmatter.required "title" Frontmatter.string
        |> Frontmatter.optional "summary" Frontmatter.string
        |> Frontmatter.withDefault "tags" [] (Frontmatter.list Frontmatter.string)


pageMeta : Frontmatter PageMeta
pageMeta =
    Frontmatter.succeed PageMeta
        |> Frontmatter.required "title" Frontmatter.string


site : Sheaf.Site
site =
    Blog.site
        { site =
            { title = "Test blog"
            , description = "A blog for tests."
            , author = { name = "Ada", email = Just "ada@example.com" }
            , language = "en"
            }
        , postFrontmatter = postMeta
        , pageFrontmatter = pageMeta
        , postsPerPage = 2
        , feedSize = Just 20
        , tags = .tags
        , feedItem = \meta -> { title = meta.title, summary = meta.summary }
        , layouts =
            { post = post
            , page = page
            , index = index
            , tag = tag
            , tags = tags
            , archive = archive
            , notFound = notFound
            }
        , components = [ callout ]
        }



-- COMPONENTS


type CalloutKind
    = Note
    | Warning


callout : Component
callout =
    Component.container "callout"
        (Component.succeed identity
            |> Component.required "kind"
                (Component.oneOf [ ( "note", Note ), ( "warning", Warning ) ])
        )
        calloutView


calloutView : CalloutKind -> List Html -> Html
calloutView kind content =
    case kind of
        Note ->
            aside [ class "callout note" ] content

        Warning ->
            aside [ class "callout warning" ] content



-- LAYOUTS


post : Document PostMeta -> Page
post document =
    layout document.meta.title
        (preview document :: List.filterMap identity [ Maybe.map Head.description document.meta.summary ])
        [ article []
            (h1 [] [ text document.meta.title ]
                :: published document
                :: cover document
                :: document.body
                ++ [ ul [] (List.map (\name -> li [] [ Blog.tagLink name [ text name ] ]) document.meta.tags) ]
            )
        ]


page : Document PageMeta -> Page
page document =
    layout document.meta.title [] [ article [] (h1 [] [ text document.meta.title ] :: document.body) ]


index : Listing PostMeta -> Page
index { items, pagination } =
    layout "Test blog" [] [ postList items, pages pagination ]


tag : String -> Listing PostMeta -> Page
tag name { items, pagination } =
    layout ("Posts tagged " ++ name) [] [ h1 [] [ text name ], postList items, pages pagination ]


tags : List (Group PostMeta) -> Page
tags groups =
    layout "Tags"
        []
        [ h1 [] [ text "Tags" ]
        , ul [] (List.map (\group -> li [] [ Blog.tagLink group.name [ text group.name ] ]) groups)
        ]


archive : List (Document PostMeta) -> Page
archive items =
    layout "Archive" [] [ h1 [] [ text "Archive" ], postList items ]


notFound : Page
notFound =
    layout "Not found" [] [ h1 [] [ text "Not found" ], p [] [ a [ siteHref "/" ] [ text "Go home" ] ] ]



-- PARTS


layout : String -> List Head.Tag -> List Html -> Page
layout title head body =
    { title = title
    , head = Head.canonical :: Head.stylesheet "/style.css" :: head
    , body =
        [ header []
            [ nav []
                [ a [ siteHref "/" ] [ text "Home" ]
                , a [ siteHref "/archive/" ] [ text "Archive" ]
                , a [ siteHref "/tags/" ] [ text "Tags" ]
                , Sheaf.link Content.Pages.about [ text "About" ]
                ]
            ]
        , main_ [] body
        , footer [] [ a [ siteHref "/feed.xml" ] [ text "RSS" ] ]
        ]
    }


preview : Document PostMeta -> Head.Tag
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


postList : List (Document PostMeta) -> Html
postList items =
    ul [] (List.map (\item -> li [] [ h2 [] [ Sheaf.link item.ref [ text item.meta.title ] ], published item ]) items)


published : Document meta -> Html
published document =
    case document.date of
        Just date ->
            time [ datetime (Date.toIsoDate date) ] [ text (Date.toIsoDate date) ]

        Nothing ->
            text ""


pages : Pagination -> Html
pages pagination =
    nav []
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
