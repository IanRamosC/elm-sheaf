module Sheaf.Markdown exposing (Body, LinkProblem, render)

{-| The Markdown body of a document, ready to be placed in a page.

The host parses and checks the Markdown, so a body is only ever obtained from a
document, and all a template can do with it is render it.

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
