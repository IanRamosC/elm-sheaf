module Sheaf.Feed exposing (Feed, fromCollection, groupedBy)

{-| A feed is an RSS and an Atom file listing the documents of a collection,
or of one of its groups, newest first, so that feed readers can follow a site
or one of its tags.

@docs Feed, fromCollection, groupedBy

-}

import Sheaf.Collection exposing (Collection)
import Sheaf.Internal.Frontmatter as Frontmatter
import Sheaf.Internal.Site as Site


{-| A feed to declare with [`Sheaf.site`](Sheaf#site) or
[`Sheaf.withFeeds`](Sheaf#withFeeds).
-}
type alias Feed =
    Site.Feed


{-| A feed of the newest `limit` published documents of a collection, or of
all of them if `limit` is `Nothing`, written as RSS at `rss` and as Atom at
`atom`. Each item gets its title and summary from the document's frontmatter,
and its content is the document's whole body, so a limit keeps the files small
for the readers that fetch them again and again.

    Feed.fromCollection { rss = "/feed.xml", atom = "/atom.xml", limit = Just 20 }
        posts
        (\meta -> { title = meta.title, summary = meta.summary })

A limit below 1 is reported when the site is built.

An item links to the document's page, so the collection needs a
[`Route.eachItem`](Sheaf-Route#eachItem) route. Items are ordered by date, so
each document needs one, as for a listing route. Every link and image in an
item's content is made absolute, because a feed reader shows it away from the
site.

-}
fromCollection : { rss : String, atom : String, limit : Maybe Int } -> Collection meta -> (meta -> { title : String, summary : Maybe String }) -> Feed
fromCollection files collection describe =
    feedOf files Nothing collection describe


{-| A feed for each group of a collection, such as each tag, at paths where
`:group` stands for the group's slug, as on the pages of a
[`Route.groupedBy`](Sheaf-Route#groupedBy) route.

    Feed.groupedBy { rss = "/tags/:group/feed.xml", atom = "/tags/:group/atom.xml", limit = Just 20 }
        { by = .tags }
        posts
        (\meta -> { title = meta.title, summary = meta.summary })

A group's feed lists its documents newest first, keeps at most `limit` of them,
and is titled after the site and the group's name, as in `My Blog · Elm`. Its
items are written as those of
[`fromCollection`](#fromCollection) are.

-}
groupedBy : { rss : String, atom : String, limit : Maybe Int } -> { by : meta -> List String } -> Collection meta -> (meta -> { title : String, summary : Maybe String }) -> Feed
groupedBy files { by } collection describe =
    feedOf files (Just (Site.groupingBy by Site.ByDate collection)) collection describe


feedOf : { rss : String, atom : String, limit : Maybe Int } -> Maybe Site.Grouping -> Collection meta -> (meta -> { title : String, summary : Maybe String }) -> Feed
feedOf files grouping (Site.Collection collection) describe =
    Site.Feed
        { rss = files.rss
        , atom = files.atom
        , limit = files.limit
        , collection = collection.name
        , grouping = grouping
        , describe =
            \document ->
                Frontmatter.decode collection.frontmatter
                    { values = document.frontmatter, positions = document.frontmatterPositions }
                    |> Result.map describe
        }
