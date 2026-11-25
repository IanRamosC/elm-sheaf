module Sheaf.Blog exposing (Config, Layouts, site, tagLink)

{-| A blog, made from the routes and feeds any site can use.

`Blog.site` reads posts from `content/posts/` and pages, such as an about
page, from `content/pages/`. Both folders must exist, even when one is empty:
Git does not keep empty folders, so commit an empty `.gitkeep` file in it.

    module Site exposing (site)

    import Sheaf
    import Sheaf.Blog as Blog
    import Sheaf.Component as Component exposing (Component)
    import Sheaf.Document exposing (Document)
    import Sheaf.Frontmatter as Frontmatter exposing (Frontmatter)
    import Sheaf.Head as Head
    import Sheaf.Html exposing (Html, a, article, aside, h1, li, main_, nav, text, ul)
    import Sheaf.Html.Attributes exposing (class, href, siteHref)
    import Sheaf.Route exposing (Group, Listing, Page)

    type alias PostMeta =
        { title : String
        , tags : List String
        , summary : Maybe String
        }

    type alias PageMeta =
        { title : String }

    postMeta : Frontmatter PostMeta
    postMeta =
        Frontmatter.succeed PostMeta
            |> Frontmatter.required "title" Frontmatter.string
            |> Frontmatter.withDefault "tags" [] (Frontmatter.list Frontmatter.string)
            |> Frontmatter.optional "summary" Frontmatter.string

    pageMeta : Frontmatter PageMeta
    pageMeta =
        Frontmatter.succeed PageMeta
            |> Frontmatter.required "title" Frontmatter.string

    site : Sheaf.Site
    site =
        Blog.site
            { site =
                { title = "My blog"
                , description = "Notes on Elm."
                , author = { name = "Ada Lovelace", email = Nothing }
                , language = "en"
                }
            , postFrontmatter = postMeta
            , pageFrontmatter = pageMeta
            , postsPerPage = 10
            , feedSize = Just 20
            , tags = .tags
            , feedItem = \meta -> { title = meta.title, summary = meta.summary }
            , layouts =
                { post = post
                , page = \document -> layout document.meta.title (article [] document.body)
                , index = \listing -> layout "My blog" (postList listing)
                , tag = \name listing -> layout name (postList listing)
                , tags = tags
                , archive = \items -> layout "Archive" (titles items)
                , notFound = layout "Not found" (h1 [] [ text "Not found" ])
                }
            , components = [ callout ]
            }

    callout : Component
    callout =
        Component.container "callout"
            (Component.succeed identity |> Component.required "kind" Component.string)
            (\kind -> aside [ class ("callout " ++ kind) ])

    post : Document PostMeta -> Page
    post document =
        layout document.meta.title
            (article []
                (h1 [] [ text document.meta.title ]
                    :: document.body
                    ++ [ ul []
                            (List.map
                                (\name -> li [] [ Blog.tagLink name [ text name ] ])
                                document.meta.tags
                            )
                       ]
                )
            )

    tags : List (Group PostMeta) -> Page
    tags groups =
        layout "Tags"
            (ul []
                (List.map (\group -> li [] [ Blog.tagLink group.name [ text group.name ] ]) groups)
            )

    postList : Listing PostMeta -> Html
    postList { items, pagination } =
        main_ []
            [ titles items
            , case pagination.next of
                Just url ->
                    a [ href url ] [ text "Older posts" ]

                Nothing ->
                    text ""
            ]

    titles : List (Document PostMeta) -> Html
    titles items =
        ul [] (List.map (\item -> li [] [ Sheaf.link item.ref [ text item.meta.title ] ]) items)

    layout : String -> Html -> Page
    layout title content =
        { title = title
        , head = [ Head.canonical, Head.stylesheet "/style.css" ]
        , body =
            [ nav []
                [ a [ siteHref "/" ] [ text "Home" ]
                , a [ siteHref "/archive/" ] [ text "Archive" ]
                ]
            , content
            ]
        }

Every layout's head also gets links to the RSS feed at `/feed.xml` and the
Atom feed at `/atom.xml`, so feed readers find them from any page.

Add routes, feeds and components of your own with
[`Sheaf.withRoutes`](Sheaf#withRoutes), [`Sheaf.withFeeds`](Sheaf#withFeeds)
and [`Sheaf.withComponents`](Sheaf#withComponents).

@docs Config, Layouts, site, tagLink

-}

import Sheaf
import Sheaf.Collection as Collection exposing (Collection)
import Sheaf.Component exposing (Component)
import Sheaf.Document exposing (Document)
import Sheaf.Feed as Feed
import Sheaf.Frontmatter exposing (Frontmatter)
import Sheaf.Head as Head
import Sheaf.Html exposing (Html)
import Sheaf.Route as Route exposing (Group, Listing, Page)


{-| What a blog needs:

  - `site` is the title, description, author and language of the whole site.
  - `postFrontmatter` and `pageFrontmatter` decode the frontmatter of
    `content/posts/` and `content/pages/`.
  - `postsPerPage` is how many posts the index and each tag's pages list.
  - `feedSize` is how many of the newest posts the feeds list, or `Nothing`
    for every post.
  - `tags` gives a post's tags, as written in its frontmatter.
  - `feedItem` gives the title and summary of a post in the feeds.
  - `layouts` turn documents into pages.
  - `components` render the directives of posts and pages, as in
    [`Sheaf.Component`](Sheaf-Component).

-}
type alias Config post page =
    { site : Sheaf.Metadata
    , postFrontmatter : Frontmatter post
    , pageFrontmatter : Frontmatter page
    , postsPerPage : Int
    , feedSize : Maybe Int
    , tags : post -> List String
    , feedItem : post -> { title : String, summary : Maybe String }
    , layouts : Layouts post page
    , components : List Component
    }


{-| A template for each kind of page:

  - `post`, at `/posts/<slug>/`, and `page`, at `/<slug>/`;
  - `index`, the newest posts at `/`, then `/page/2/` and on;
  - `tag`, the posts with one tag, at `/tags/<tag>/`, given the tag's name;
  - `tags`, every tag and its posts, at `/tags/`;
  - `archive`, every post, at `/archive/`;
  - `notFound`, the page served for any URL with no page, at `/404.html`.

A page's slug must not be one of the blog's own folders, such as `archive` or
`tags`: both would be written to the same file, which is reported when the
site is built.

-}
type alias Layouts post page =
    { post : Document post -> Page
    , page : Document page -> Page
    , index : Listing post -> Page
    , tag : String -> Listing post -> Page
    , tags : List (Group post) -> Page
    , archive : List (Document post) -> Page
    , notFound : Page
    }


{-| A blog with this configuration.
-}
site : Config post page -> Sheaf.Site
site config =
    let
        posts : Collection post
        posts =
            Collection.named "posts" config.postFrontmatter

        pages : Collection page
        pages =
            Collection.named "pages" config.pageFrontmatter

        layouts : Layouts post page
        layouts =
            config.layouts

        withFeeds : Page -> Page
        withFeeds =
            withFeedLinks config.site.title
    in
    Sheaf.site
        { metadata = config.site
        , routes =
            [ Route.paginated "/" { perPage = config.postsPerPage } posts (layouts.index >> withFeeds)
            , Route.eachItem "/posts/:slug/" posts (layouts.post >> withFeeds)
            , Route.eachItem "/:slug/" pages (layouts.page >> withFeeds)
            , Route.allGroups "/tags/" config.tags posts (layouts.tags >> withFeeds)
            , Route.groupedBy tagPattern
                { by = config.tags, perPage = Just config.postsPerPage }
                posts
                (\name -> layouts.tag name >> withFeeds)
            , Route.allItems "/archive/" posts (layouts.archive >> withFeeds)
            , Route.notFound (withFeeds layouts.notFound)
            ]
        , feeds = [ Feed.fromCollection { rss = rssPath, atom = atomPath, limit = config.feedSize } posts config.feedItem ]
        , components = config.components
        }


withFeedLinks : String -> Page -> Page
withFeedLinks title page =
    { page
        | head =
            page.head
                ++ [ Head.rssFeed { title = title, path = rssPath }
                   , Head.atomFeed { title = title, path = atomPath }
                   ]
    }


rssPath : String
rssPath =
    "/feed.xml"


atomPath : String
atomPath =
    "/atom.xml"


tagPattern : String
tagPattern =
    "/tags/:group/"


{-| A link to the page of a tag:

    Blog.tagLink "Elm" [ text "Elm" ]

Sheaf computes slugs only for values written in some document's frontmatter,
so the tag must be spelled exactly as some document spells it: if every post
writes `elm`, `Blog.tagLink "Elm"` is reported as `MISSING SLUG`. A tag whose
only posts are drafts has no page, so a link to it fails the build too. So
templates normally link to the tags of a post's frontmatter:

    List.map (\name -> Blog.tagLink name [ text name ]) post.meta.tags

-}
tagLink : String -> List Html -> Html
tagLink =
    Sheaf.groupLink tagPattern
