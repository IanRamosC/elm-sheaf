module Site exposing (site)

import Sheaf
import Sheaf.Collection as Collection exposing (Collection)
import Sheaf.Document exposing (Document)
import Sheaf.Feed as Feed
import Sheaf.Frontmatter as Frontmatter
import Sheaf.Head as Head
import Sheaf.Html exposing (Html, a, article, h1, li, main_, nav, p, text, ul)
import Sheaf.Html.Attributes exposing (href, siteHref)
import Sheaf.Route as Route exposing (Group, Listing, Page)


type alias NoteMeta =
    { title : String
    , topics : List String
    }


notes : Collection NoteMeta
notes =
    Collection.named "notes"
        (Frontmatter.succeed NoteMeta
            |> Frontmatter.required "title" Frontmatter.string
            |> Frontmatter.withDefault "topics" [] (Frontmatter.list Frontmatter.string)
        )


site : Sheaf.Site
site =
    Sheaf.site
        { metadata =
            { title = "Notes"
            , description = "Notes without the blog preset."
            , author = { name = "Ada", email = Nothing }
            , language = "en"
            }
        , routes =
            [ Route.single "/" home
            , Route.eachItem "/notes/:slug/" notes note
            , Route.paginated "/notes/" { perPage = 2 } notes noteList
            , Route.groupedBy "/topics/:group/" { by = .topics, perPage = Nothing } notes topic
            , Route.allGroups "/topics/" .topics notes topics
            , Route.allItems "/archive/" notes archive
            , Route.notFound (layout "Not found" [ h1 [] [ text "Not found" ] ])
            ]
        , feeds =
            [ Feed.fromCollection { rss = "/notes/feed.xml", atom = "/notes/atom.xml", limit = Nothing }
                notes
                (\meta -> { title = meta.title, summary = Nothing })
            ]
        , components = []
        }


home : Page
home =
    layout "Notes"
        [ h1 [] [ text "Notes" ]
        , p [] [ a [ siteHref "/notes/" ] [ text "Read the notes" ] ]
        ]


note : Document NoteMeta -> Page
note document =
    layout document.meta.title
        [ article []
            (h1 [] [ text document.meta.title ]
                :: document.body
                ++ [ ul [] (List.map (\name -> li [] [ topicLink name ]) document.meta.topics) ]
            )
        ]


noteList : Listing NoteMeta -> Page
noteList { items, pagination } =
    layout "All notes"
        [ titles items
        , case pagination.next of
            Just url ->
                a [ href url ] [ text "More notes" ]

            Nothing ->
                text ""
        ]


topic : String -> Listing NoteMeta -> Page
topic name { items } =
    layout name [ h1 [] [ text name ], titles items ]


topics : List (Group NoteMeta) -> Page
topics groups =
    layout "Topics" [ ul [] (List.map (\group -> li [] [ topicLink group.name ]) groups) ]


archive : List (Document NoteMeta) -> Page
archive items =
    layout "Archive" [ titles items ]


layout : String -> List Html -> Page
layout title body =
    { title = title
    , head = [ Head.canonical, Head.rssFeed { title = "Notes", path = "/notes/feed.xml" } ]
    , body =
        [ nav []
            [ a [ siteHref "/" ] [ text "Home" ]
            , a [ siteHref "/topics/" ] [ text "Topics" ]
            , a [ siteHref "/archive/" ] [ text "Archive" ]
            ]
        , main_ [] body
        ]
    }


titles : List (Document NoteMeta) -> Html
titles items =
    ul [] (List.map (\item -> li [] [ Sheaf.link item.ref [ text item.meta.title ] ]) items)


topicLink : String -> Html
topicLink name =
    Sheaf.groupLink "/topics/:group/" name [ text name ]
