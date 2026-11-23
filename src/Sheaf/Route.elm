module Sheaf.Route exposing (Route, Page, single, eachItem)

{-| Routes decide which pages a site has and where they are written.

A pattern ending in `/` is a folder, written as its `index.html`: `/` becomes
`index.html` and `/about/` becomes `about/index.html`. Any other pattern is the
file itself, as in `/404.html`. Links get the site's base path in front, but
the files do not, because the host serves them from there.

@docs Route, Page, single, eachItem

-}

import Sheaf.Collection exposing (Collection)
import Sheaf.Document exposing (Document)
import Sheaf.Html exposing (Html)
import Sheaf.Internal.Frontmatter as Frontmatter
import Sheaf.Internal.Protocol as Protocol
import Sheaf.Internal.Site as Site
import Sheaf.Ref as Ref
import Time


{-| One or more pages of the site.
-}
type alias Route =
    Site.Route


{-| What a template returns: the page's title and the content of its `body`.
-}
type alias Page =
    { title : String
    , body : List Html
    }


{-| A single page at a fixed pattern.

    Route.single "/about/" aboutPage

-}
single : String -> Page -> Route
single pattern page =
    Site.Single { pattern = pattern, page = page }


{-| A page for every published document of a collection, at a pattern where
`:slug` stands for the document's slug.

    Route.eachItem "/posts/:slug/" posts Theme.Post.view

This is also where links to the collection's documents point. When several
`eachItem` routes use the same collection, links use the first in the site's
list of routes.

-}
eachItem : String -> Collection meta -> (Document meta -> Page) -> Route
eachItem pattern (Site.Collection collection) template =
    Site.EachItem
        { pattern = pattern
        , collection = collection.name
        , templateFor =
            \document ->
                Frontmatter.decode collection.frontmatter
                    { values = document.frontmatter, positions = document.frontmatterPositions }
                    |> Result.map
                        (\meta body ->
                            template
                                { ref = Ref.fromId document.id
                                , slug = document.slug
                                , date = Maybe.map toDate document.date
                                , meta = meta
                                , body = body
                                }
                        )
        }


toDate : Protocol.Date -> Sheaf.Document.Date
toDate date =
    { posixMillis = Time.posixToMillis date.posix, isoDate = date.isoDate }
