module Sheaf.Document exposing (Document)

{-| A document of a collection, as an item template receives it.

@docs Document

-}

import Sheaf.Date exposing (Date)
import Sheaf.Html exposing (Html)
import Sheaf.Ref exposing (Ref)


{-| One Markdown file.

  - `ref` links to it with [`Sheaf.link`](Sheaf#link).
  - `slug` is the last part of its URL.
  - `date` comes from the `date` frontmatter key or the file name.
  - `updated` comes from the `updated` frontmatter key, or is `date` when there
    is none.
  - `meta` is its frontmatter, decoded by its collection.
  - `body` is its Markdown, rendered, with links to other documents resolved.

-}
type alias Document meta =
    { ref : Ref
    , slug : String
    , date : Maybe Date
    , updated : Maybe Date
    , meta : meta
    , body : List Html
    }
