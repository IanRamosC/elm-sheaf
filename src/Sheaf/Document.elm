module Sheaf.Document exposing (Document, Heading, Neighbour)

{-| A document of a collection, as an item template receives it.

@docs Document, Heading, Neighbour

-}

import Sheaf.Date exposing (Date)
import Sheaf.Html exposing (Html)
import Sheaf.Image exposing (Image)
import Sheaf.Ref exposing (Ref)


{-| One Markdown file.

  - `ref` links to it with [`Sheaf.link`](Sheaf#link).
  - `slug` is the last part of its URL.
  - `date` comes from the `date` frontmatter key or the file name.
  - `updated` comes from the `updated` frontmatter key, or is `date` when there
    is none.
  - `meta` is its frontmatter, decoded by its collection.
  - `image` comes from the `image` frontmatter key; see
    [`Sheaf.Image`](Sheaf-Image).
  - `headings` are the headings of its body, in order; see
    [`Heading`](#Heading).
  - `previous` and `next` are the documents before and after it in its
    collection's reading order; see [`Neighbour`](#Neighbour).
  - `body` is its Markdown, rendered, with links to other documents resolved.

-}
type alias Document meta =
    { ref : Ref
    , slug : String
    , date : Maybe Date
    , updated : Maybe Date
    , meta : meta
    , image : Maybe Image
    , headings : List Heading
    , previous : Maybe (Neighbour meta)
    , next : Maybe (Neighbour meta)
    , body : List Html
    }


{-| A heading of a document's body, for a table of contents.

`depth` is 1 for `#` to 6 for `######`, and `id` is the heading's `id` in the
rendered body, so `"#" ++ id` links to it. `text` is its plain text: markup is
dropped, inline code is kept as text, and images and footnote references are
left out.

Every heading is listed, including those inside components, blockquotes and
lists, so a table of contents keeps the depths it wants:

    tableOfContents : List Heading -> Html
    tableOfContents headings =
        headings
            |> List.filter (\heading -> (heading.depth == 2 || heading.depth == 3) && heading.id /= "")
            |> List.map (\heading -> li [] [ a [ href ("#" ++ heading.id) ] [ text heading.text ] ])
            |> ul []

A heading with no letters or digits, such as `## !!!`, has an empty `id`, and
no link to itself on the page, so the table of contents leaves it out.

-}
type alias Heading =
    { depth : Int
    , id : String
    , text : String
    }


{-| The document before or after another, for links such as "older" and
"newer".

A collection is read oldest to newest, by date, so `previous` is the older
document and `next` the newer one. A collection given
[`Collection.orderedBy`](Sheaf-Collection#orderedBy) is read from the lowest
number to the highest. The first document has no `previous`, and the last no
`next`.

When a collection is read by date and any of its published documents has no
date, there is no order to follow, and every document's `previous` and `next`
are `Nothing`. This is not a problem: a collection of pages usually has no
dates.

Only published documents are neighbours, so drafts are neighbours only in a
build that includes them.

    case document.previous of
        Just older ->
            Sheaf.link older.ref [ text ("← " ++ older.meta.title) ]

        Nothing ->
            text ""

-}
type alias Neighbour meta =
    { ref : Ref
    , slug : String
    , date : Maybe Date
    , meta : meta
    }
