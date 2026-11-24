module Sheaf.Head exposing
    ( Tag
    , description, canonical
    , openGraph, Kind(..), twitterCard, Card(..)
    , stylesheet, rssFeed, atomFeed
    , meta
    )

{-| Tags for a page's `<head>`.

Every page's head starts with `<meta charset="utf-8">`, the viewport
`<meta name="viewport" content="width=device-width, initial-scale=1">` and the
page's `<title>`. The tags in its `head` follow, in order:

    { title = post.meta.title
    , head =
        [ Head.description post.meta.summary
        , Head.canonical
        , Head.stylesheet "/style.css"
        ]
    , body = post.body
    }


## Paths

A path that starts with a single `/`, such as `/style.css`, is a path from the
root of the site. It gets the site's base path in front, and the origin too
where a full URL is needed, as for `og:image`. An `http://` or `https://` URL
is used as given. Any other path, such as `style.css` or
`//cdn.example.com/style.css`, is reported when the page is built.

@docs Tag


# Search engines

@docs description, canonical


# Link previews

@docs openGraph, Kind, twitterCard, Card


# Linked files

@docs stylesheet, rssFeed, atomFeed


# Anything else

@docs meta

-}

import Sheaf.Date exposing (Date)
import Sheaf.Internal.Head as Internal


{-| A tag in a page's `<head>`.
-}
type alias Tag =
    Internal.Tag


{-| `<meta name="description">`, the summary search engines show.
-}
description : String -> Tag
description =
    Internal.Description


{-| `<link rel="canonical">`, the page's own absolute URL, such as
`https://example.com/blog/posts/hello/`.

On the [`Route.notFound`](Sheaf-Route#notFound) page it renders nothing,
because that page is served in place of any missing page and has no URL of its
own.

-}
canonical : Tag
canonical =
    Internal.Canonical


{-| The Open Graph tags that link previews read: `og:title`,
`og:description`, `og:image`, `og:url` (this page's absolute URL, left out on
the `Route.notFound` page, as for `canonical`) and `og:type`. An article also
gets `article:published_time` and `article:modified_time`, in UTC.

For a post whose `summary` is a `String`, given the date it was published:

    articlePreview : Date -> Document PostMeta -> Head.Tag
    articlePreview published post =
        Head.openGraph
            { title = post.meta.title
            , description = Just post.meta.summary
            , image = Just "/covers/hello.png"
            , kind = Head.Article { published = published, modified = post.updated }
            }

-}
openGraph : { title : String, description : Maybe String, image : Maybe String, kind : Kind } -> Tag
openGraph og =
    Internal.OpenGraph
        { title = og.title
        , description = og.description
        , image = og.image
        , type_ =
            case og.kind of
                Website ->
                    Internal.Website

                Article dates ->
                    Internal.Article dates
        }


{-| What a page is, for `og:type`: a page of the site, or an article with the
dates it was published and last changed.
-}
type Kind
    = Website
    | Article { published : Date, modified : Maybe Date }


{-| `<meta name="twitter:card">`, the kind of card shown for the page. The
card's title, description and image come from [`openGraph`](#openGraph).
-}
twitterCard : Card -> Tag
twitterCard card =
    Internal.TwitterCard
        (case card of
            Summary ->
                Internal.Summary

            SummaryLargeImage ->
                Internal.SummaryLargeImage
        )


{-| A small card with a thumbnail, or one with a large image above the title.
-}
type Card
    = Summary
    | SummaryLargeImage


{-| `<link rel="stylesheet">`, such as `Head.stylesheet "/style.css"` for
`static/style.css`.
-}
stylesheet : String -> Tag
stylesheet =
    Internal.Stylesheet


{-| `<link rel="alternate">` to an RSS feed, so feed readers can find it.
-}
rssFeed : { title : String, path : String } -> Tag
rssFeed =
    Internal.AlternateFeed Internal.Rss


{-| `<link rel="alternate">` to an Atom feed, so feed readers can find it.
-}
atomFeed : { title : String, path : String } -> Tag
atomFeed =
    Internal.AlternateFeed Internal.Atom


{-| Any other `<meta name content>`, such as
`Head.meta { name = "author", content = "Ada Lovelace" }`.
-}
meta : { name : String, content : String } -> Tag
meta =
    Internal.Meta
