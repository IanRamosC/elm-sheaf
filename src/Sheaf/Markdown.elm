module Sheaf.Markdown exposing (Body, LinkProblem, render)

{-| Rendering a Markdown body to HTML, with its links to other documents
resolved.

The host parses and checks each document's Markdown, and Sheaf renders it
before calling a template, so a template receives `Document.body` as HTML
already. This module is the renderer itself; a `Body` is opaque, and there is
no way yet for a template to obtain one.

@docs Body, LinkProblem, render

-}

import Sheaf.Html exposing (Html)
import Sheaf.Internal.Markdown as Internal
import Sheaf.Ref exposing (Ref)


{-| The Markdown of one document.
-}
type alias Body =
    Internal.Body


{-| A link to a document that has no page, with the place it was written.

`id` is the target as `"<collection>/<slug>"`.

-}
type alias LinkProblem =
    Internal.LinkProblem


{-| Turn a body into HTML.

The function resolves a link to another document to its URL, and returns
`Nothing` when that document has none. Every such link is returned in the
`Err`, not just the first.

Code blocks become `pre > code.language-<lang>`, headings get their `id`,
task-list items get a disabled checkbox and footnotes are laid out as GitHub
does.

-}
render : (Ref -> Maybe String) -> Body -> Result (List LinkProblem) (List Html)
render =
    Internal.render
