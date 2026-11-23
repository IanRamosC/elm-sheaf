module Sheaf.Collection exposing (Collection, named)

{-| A collection is a folder of Markdown documents in `content/`, such as
`content/posts/`.

@docs Collection, named

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
    Site.Collection { name = name, frontmatter = frontmatter }
