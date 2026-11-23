module Sheaf.Document exposing (Document, Date)

{-| A document of a collection, as an item template receives it.

@docs Document, Date

-}

import Sheaf.Html exposing (Html)
import Sheaf.Ref exposing (Ref)


{-| One Markdown file.

  - `ref` links to it with [`Sheaf.link`](Sheaf#link).
  - `slug` is the last part of its URL.
  - `date` comes from the `date` frontmatter key or the file name.
  - `meta` is its frontmatter, decoded by its collection.
  - `body` is its Markdown, rendered, with links to other documents resolved.

-}
type alias Document meta =
    { ref : Ref
    , slug : String
    , date : Maybe Date
    , meta : meta
    , body : List Html
    }


{-| A moment, in milliseconds since the Unix epoch, and the calendar date as
the author wrote it (`2026-11-23`).
-}
type alias Date =
    { posixMillis : Int
    , isoDate : String
    }
