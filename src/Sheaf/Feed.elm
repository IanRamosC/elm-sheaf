module Sheaf.Feed exposing (Feed, fromCollection)

{-| A feed is an RSS and an Atom file listing the documents of a collection,
newest first, so that feed readers can follow a site.

@docs Feed, fromCollection

-}

import Sheaf.Collection exposing (Collection)
import Sheaf.Internal.Frontmatter as Frontmatter
import Sheaf.Internal.Site as Site


{-| A feed to declare with [`Sheaf.site`](Sheaf#site) or
[`Sheaf.withFeeds`](Sheaf#withFeeds).
-}
type alias Feed =
    Site.Feed


{-| A feed of every published document of a collection, written as RSS at
`rss` and as Atom at `atom`. Each item gets its title and summary from the
document's frontmatter, and its content is the document's whole body.

    Feed.fromCollection { rss = "/feed.xml", atom = "/atom.xml" }
        posts
        (\meta -> { title = meta.title, summary = meta.summary })

An item links to the document's page, so the collection needs a
[`Route.eachItem`](Sheaf-Route#eachItem) route. Items are ordered by date, so
each document needs one, as for a listing route. Every link and image in an
item's content is made absolute, because a feed reader shows it away from the
site.

-}
fromCollection : { rss : String, atom : String } -> Collection meta -> (meta -> { title : String, summary : Maybe String }) -> Feed
fromCollection files (Site.Collection collection) describe =
    Site.Feed
        { rss = files.rss
        , atom = files.atom
        , collection = collection.name
        , describe =
            \document ->
                Frontmatter.decode collection.frontmatter
                    { values = document.frontmatter, positions = document.frontmatterPositions }
                    |> Result.map describe
        }
