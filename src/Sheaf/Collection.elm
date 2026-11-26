module Sheaf.Collection exposing (Collection, named, orderedBy)

{-| A collection is a folder of Markdown documents in `content/`, such as
`content/posts/`.

@docs Collection, named, orderedBy

-}

import Sheaf.Frontmatter exposing (Frontmatter)
import Sheaf.Internal.Site as Site


{-| A collection whose documents have frontmatter of type `meta`.
-}
type alias Collection meta =
    Site.Collection meta


{-| The collection in the folder `content/<name>/`, with the frontmatter its
documents must have.

    posts : Collection PostMeta
    posts =
        Collection.named "posts" postMeta

A name with no folder, and a folder that no route uses, are both reported when
the site is built.

-}
named : String -> Frontmatter meta -> Collection meta
named name frontmatter =
    Site.Collection { name = name, frontmatter = frontmatter, order = Nothing }


{-| Order the collection's documents by a number from their frontmatter,
lowest first, instead of newest first. Documents with the same number are
ordered by slug.

    docs : Collection DocMeta
    docs =
        Collection.named "docs" docMeta
            |> Collection.orderedBy .order

Listing and grouped routes over this collection follow the order, and its
documents need no date. Feeds are still newest first, so a collection in a
feed still needs dates.

-}
orderedBy : (meta -> Int) -> Collection meta -> Collection meta
orderedBy keyOf (Site.Collection collection) =
    Site.Collection { collection | order = Just keyOf }
