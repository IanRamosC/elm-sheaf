# Templates

A Sheaf site is an Elm value: the site's metadata, its routes, its feeds and its
components. This page shows how the pieces fit together. The reference for each
function is its documentation comment in [`src/Sheaf/`](../../src/Sheaf), which
will be on the Elm package website once the package is published.

## `Site.elm`

Every site has a `src/Site.elm` that exposes `site : Sheaf.Site`. It can't be
called `main`, because Elm rejects any `main` that isn't a program; Sheaf
generates the program that runs it into `.sheaf/gen/`, along with a module per
collection.

The starter's `Site.elm` uses the blog preset:

```elm
site : Sheaf.Site
site =
    Blog.site
        { site = metadata
        , postFrontmatter = postFrontmatter
        , pageFrontmatter = pageFrontmatter
        , postsPerPage = 10
        , feedSize = Just 20
        , tags = .tags
        , feedItem = \post -> { title = post.title, summary = post.summary }
        , layouts =
            { post = Pages.post metadata
            , page = Pages.page metadata
            , index = Pages.index metadata
            , tag = Pages.tag metadata
            , tags = Pages.tags metadata
            , archive = Pages.archive metadata
            , notFound = Pages.notFound metadata
            }
        , components = [ Components.callout ]
        }


metadata : Sheaf.Metadata
metadata =
    { title = "My blog"
    , description = "Notes, written in Markdown and built with Sheaf."
    , author = { name = "Your Name", email = Nothing }
    , language = "en"
    }
```

The metadata is the site's own: the feeds use it, and `language` becomes the
`lang` of every page.

## The blog preset

`Sheaf.Blog` reads posts from `content/posts/` and pages from `content/pages/`,
each with the frontmatter decoder you give it, and declares these routes:

| Layout | Renders | At |
|---|---|---|
| `post` | one post | `/posts/<slug>/` |
| `page` | one page, such as the about page | `/<slug>/` |
| `index` | the newest posts, `postsPerPage` at a time | `/`, then `/page/2/` and on |
| `tag` | the posts with one tag, paginated the same way | `/tags/<tag>/` |
| `tags` | every tag and its posts | `/tags/` |
| `archive` | every post | `/archive/` |
| `notFound` | the page for any address with no page | `/404.html` |

It also writes an RSS feed at `/feed.xml` and an Atom feed at `/atom.xml`, with
the newest `feedSize` posts (`Nothing` keeps every post), and adds links to both
to the head of every page. `tags` says where a post's tags are, and `feedItem`
gives each post's title and summary in the feeds.

A page's slug can't be one of the blog's own folders, such as `archive` or
`tags`: both would be written to the same file, which is `DUPLICATE PAGE`.

The preset is built only from what the package exposes, so you can add to it
with `Sheaf.withRoutes`, `Sheaf.withFeeds` and `Sheaf.withComponents`, or build
a site without it (see [Routes](#routes)).

## Pages

Every template returns a `Page`, a record of the page's title, the tags of its
`<head>`, and its body. The `routes` fixture in this repository wraps every page
in the same frame:

```elm
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
```

Sheaf adds `<meta charset="utf-8">` and a viewport tag before your head tags,
and writes the page as a complete HTML document.

Templates are written with `Sheaf.Html` and `Sheaf.Html.Attributes`, which
mirror `elm/html` (`div`, `a`, `class`, `href`, `text` and so on) but render to
a string. `Html` has no message type, because these pages never run Elm in the
browser. There is no way to insert raw HTML. An element or attribute name that
isn't valid HTML, or a `<script>` or `<style>` element, whose content can't be
escaped, is `INVALID HTML`; put styles and scripts in files under `static/` and
link to them.

A template that receives a document gets a `Document meta`:

```elm
type alias Document meta =
    { ref : Ref
    , slug : String
    , date : Maybe Date
    , updated : Maybe Date
    , meta : meta
    , image : Maybe Image
    , body : List Html
    }
```

`meta` is what your frontmatter decoder produced, `body` is the rendered
Markdown, and `image` is the cover from the `image` key (see
[Static files and images](static-files-and-images.md)).

### Paths and links

A site can be served under a path, such as `https://example.com/blog/` (see
[Configuration](configuration.md)). Link to the site's own pages and files with
`siteHref` and `siteSrc`, which add that base path:

```elm
li [] [ a [ siteHref "/archive/" ] [ text "Archive" ] ]
```

Their path must start with a single `/`, or the page is `INVALID HTML`. Plain `href` and `src` are left as
written, for links to other sites.

Link to a document with `Sheaf.link` and the reference Sheaf generates for it.
`content/pages/about.md` becomes `Content.Pages.about`, so this line from the
starter's `Theme/Layout.elm` fails to compile if the about page is renamed or
deleted:

```elm
li [] [ Sheaf.link Content.Pages.about [ text "About" ] ]
```

Every document has a reference, drafts included, so `sheaf dev` and
`sheaf build` compile the same code. Linking to a draft from a published page
is reported when the page is rendered, as `LINK TO DRAFT`.

Link to a tag's page with `Blog.tagLink`, or to any group with
`Sheaf.groupLink`. Sheaf computes a slug for each value written in
frontmatter, so link with the value as some document writes it; a value no
document uses is `MISSING SLUG`, and a group whose documents are all drafts is
`LINK TO EMPTY GROUP`. The starter links to the tags of each post:

```elm
tagLinks : List String -> List Html
tagLinks names =
    List.map (\name -> span [ class "tag" ] [ Blog.tagLink name [ text name ] ]) names
```

### The head

`Sheaf.Head` makes the tags of a page's `<head>`: `description`, `canonical`,
`stylesheet`, `icon`, `rssFeed`, `atomFeed`, `meta`, and Open Graph and Twitter
tags for link previews. The starter's layout starts every page with:

```elm
Head.canonical
    :: Head.description page.description
    :: Head.stylesheet "/style.css"
    :: Head.icon { path = "/favicon.svg", mediaType = "image/svg+xml" }
    :: page.head
```

and its post template adds an Open Graph preview:

```elm
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
```

Paths given to the head are site paths, starting with `/`, and the base path
and the site's address are added for you; a path that is neither a site path
nor an `http` or `https` URL is `INVALID HTML`. `rssFeed` and `atomFeed` must
name a feed the site declares, or the page is `UNKNOWN FEED`.

## Components

A component turns a Markdown directive into HTML with a view you write. Its
attributes are decoded into your own types with `Sheaf.Component`, which works
like `Sheaf.Frontmatter`. The starter's callout:

```elm
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
```

`Component.container` takes a view of the attributes and the rendered content
inside the directive; `Component.leaf` takes a view of the attributes alone.
Attributes are read with `required`, `optional` and `withDefault`, and values
with `string`, `int`, `oneOf`, `map` and `validate`. A site lists its
components in `components`, as above.

A component name starts with a letter, followed by letters, digits, `-` and
`_`; another name is `BAD COMPONENT NAME`, and two components with the same
name are `DUPLICATE COMPONENT`. How Markdown uses components, and what each
mistake is reported as, is in [Content](content.md#components).

## Routes

Without the preset, a site is `Sheaf.site` with your own collections and
routes. The [`routes` fixture](../../cli/test/fixtures/routes/src/Site.elm)
builds notes with topics this way:

```elm
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
```

The route kinds are:

- `Route.single`: one page at a fixed path.
- `Route.eachItem`: a page per document; `:slug` in the pattern is the
  document's slug. A collection needs one of these for links to its documents.
- `Route.paginated`: the documents, newest first, `perPage` at a time. Page `k`
  is at `page/<k>/` under the first page. The template gets a `Listing`: the
  documents and a `Pagination` with the page number, the number of pages and
  the URLs of the previous and next pages.
- `Route.groupedBy`: a page per group, where `by` gives a document's values,
  such as its tags, and `:group` is the value's slug. With `perPage = Just n`
  each group is paginated like `Route.paginated`.
- `Route.allItems`: every document on one page.
- `Route.allGroups`: every group, with its documents, on one page.
- `Route.notFound`: the page written to `/404.html`, which most hosts serve for
  a missing address. It's left out of the sitemap.

Every page path ends in `/` and is written as `index.html` in that folder. A
pattern that can't be written, such as one without a leading `/`, or one under
`/_sheaf/`, which Sheaf keeps for its own files, is `BAD ROUTE`. Two routes
that would write the same file, compared without regard to case, are
`DUPLICATE PAGE`.

Group values are turned into slugs by Sheaf: `Elm` and `elm` share the page
`elm`, and so do `open source` and `open-source`. Two different values that
only collide because of punctuation, such as `C` and `C++`, are
`GROUP COLLISION`, and a value with no letter or digit is `EMPTY GROUP SLUG`.

Collections listed by `paginated`, `groupedBy`, `allItems`, `allGroups` or a
feed are sorted by date, so their documents need one (see
[Content](content.md#dates-and-drafts)).

## Feeds

`Feed.fromCollection` declares an RSS 2.0 feed and an Atom feed of a
collection, at the two paths you give, with the newest `limit` documents
(`Nothing` keeps all of them). Each item holds the document's full HTML, with
every link made absolute. The function you pass gives each item's title and
summary.

A feed's items link to their documents, so the collection needs a
`Route.eachItem` route; without one, the feed is `NO PAGE FOR FEED`. Every site
also gets a `sitemap.xml` of every page except the 404 page.
