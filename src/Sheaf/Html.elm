module Sheaf.Html exposing
    ( Html, Attribute
    , text, node
    , div, span, p, a, h1, h2, h3, h4, h5, h6
    , header, footer, main_, nav, article, section, aside
    , ul, ol, li
    , pre, code, em, strong, del, blockquote, small, sup, time
    , hr, br, img, input
    , table, thead, tbody, tr, th, td
    , figure, figcaption
    , toString, document
    )

{-| HTML that can be rendered to a string, with the names of `elm/html`.

Pages never run in a browser, so there are no events and no message type.
There is deliberately no way to insert raw HTML.

@docs Html, Attribute
@docs text, node


# Sections

@docs div, span, p, a, h1, h2, h3, h4, h5, h6
@docs header, footer, main_, nav, article, section, aside


# Lists

@docs ul, ol, li


# Inline text

@docs pre, code, em, strong, del, blockquote, small, sup, time


# Void elements

They have no content, so any children are ignored.

@docs hr, br, img, input


# Tables

@docs table, thead, tbody, tr, th, td


# Figures

@docs figure, figcaption


# Rendering

@docs toString, document

-}

import Sheaf.Internal.Html as Internal


{-| A piece of a page.
-}
type alias Html =
    Internal.Html


{-| An attribute of an element. See `Sheaf.Html.Attributes`.
-}
type alias Attribute =
    Internal.Attribute


{-| Plain text. It is escaped when rendered.
-}
text : String -> Html
text =
    Internal.text


{-| An element with any tag name, like `node "my-element"`.

A tag name that is not valid, or `script` and `style` (their content cannot be
escaped, so put such files in `static/`), is reported when the page is built.

-}
node : String -> List Attribute -> List Html -> Html
node =
    Internal.node


{-| Render a tree as HTML.

A [`Sheaf.link`](Sheaf#link) only gets its URL when the site is built, so
here it renders as an `<a>` without an `href`.

-}
toString : Html -> String
toString =
    Internal.toString


{-| Render a whole page, starting with the doctype.

The `head` is preceded by `<meta charset="utf-8">`, so templates do not need
to add it.

-}
document : { lang : String, head : List Html, body : List Html } -> String
document =
    Internal.document


{-| Same as `elm/html`'s `div`.
-}
div : List Attribute -> List Html -> Html
div =
    node "div"


{-| Same as `elm/html`'s `span`.
-}
span : List Attribute -> List Html -> Html
span =
    node "span"


{-| Same as `elm/html`'s `p`.
-}
p : List Attribute -> List Html -> Html
p =
    node "p"


{-| Same as `elm/html`'s `a`.
-}
a : List Attribute -> List Html -> Html
a =
    node "a"


{-| Same as `elm/html`'s `h1`.
-}
h1 : List Attribute -> List Html -> Html
h1 =
    node "h1"


{-| Same as `elm/html`'s `h2`.
-}
h2 : List Attribute -> List Html -> Html
h2 =
    node "h2"


{-| Same as `elm/html`'s `h3`.
-}
h3 : List Attribute -> List Html -> Html
h3 =
    node "h3"


{-| Same as `elm/html`'s `h4`.
-}
h4 : List Attribute -> List Html -> Html
h4 =
    node "h4"


{-| Same as `elm/html`'s `h5`.
-}
h5 : List Attribute -> List Html -> Html
h5 =
    node "h5"


{-| Same as `elm/html`'s `h6`.
-}
h6 : List Attribute -> List Html -> Html
h6 =
    node "h6"


{-| Same as `elm/html`'s `ul`.
-}
ul : List Attribute -> List Html -> Html
ul =
    node "ul"


{-| Same as `elm/html`'s `ol`.
-}
ol : List Attribute -> List Html -> Html
ol =
    node "ol"


{-| Same as `elm/html`'s `li`.
-}
li : List Attribute -> List Html -> Html
li =
    node "li"


{-| Same as `elm/html`'s `header`.
-}
header : List Attribute -> List Html -> Html
header =
    node "header"


{-| Same as `elm/html`'s `footer`.
-}
footer : List Attribute -> List Html -> Html
footer =
    node "footer"


{-| Same as `elm/html`'s `main`.
-}
main_ : List Attribute -> List Html -> Html
main_ =
    node "main"


{-| Same as `elm/html`'s `nav`.
-}
nav : List Attribute -> List Html -> Html
nav =
    node "nav"


{-| Same as `elm/html`'s `article`.
-}
article : List Attribute -> List Html -> Html
article =
    node "article"


{-| Same as `elm/html`'s `section`.
-}
section : List Attribute -> List Html -> Html
section =
    node "section"


{-| Same as `elm/html`'s `aside`.
-}
aside : List Attribute -> List Html -> Html
aside =
    node "aside"


{-| Same as `elm/html`'s `pre`.
-}
pre : List Attribute -> List Html -> Html
pre =
    node "pre"


{-| Same as `elm/html`'s `code`.
-}
code : List Attribute -> List Html -> Html
code =
    node "code"


{-| Same as `elm/html`'s `em`.
-}
em : List Attribute -> List Html -> Html
em =
    node "em"


{-| Same as `elm/html`'s `strong`.
-}
strong : List Attribute -> List Html -> Html
strong =
    node "strong"


{-| Same as `elm/html`'s `del`.
-}
del : List Attribute -> List Html -> Html
del =
    node "del"


{-| Same as `elm/html`'s `blockquote`.
-}
blockquote : List Attribute -> List Html -> Html
blockquote =
    node "blockquote"


{-| Same as `elm/html`'s `hr`.
-}
hr : List Attribute -> List Html -> Html
hr =
    node "hr"


{-| Same as `elm/html`'s `br`.
-}
br : List Attribute -> List Html -> Html
br =
    node "br"


{-| Same as `elm/html`'s `img`.
-}
img : List Attribute -> List Html -> Html
img =
    node "img"


{-| Same as `elm/html`'s `table`.
-}
table : List Attribute -> List Html -> Html
table =
    node "table"


{-| Same as `elm/html`'s `thead`.
-}
thead : List Attribute -> List Html -> Html
thead =
    node "thead"


{-| Same as `elm/html`'s `tbody`.
-}
tbody : List Attribute -> List Html -> Html
tbody =
    node "tbody"


{-| Same as `elm/html`'s `tr`.
-}
tr : List Attribute -> List Html -> Html
tr =
    node "tr"


{-| Same as `elm/html`'s `th`.
-}
th : List Attribute -> List Html -> Html
th =
    node "th"


{-| Same as `elm/html`'s `td`.
-}
td : List Attribute -> List Html -> Html
td =
    node "td"


{-| Same as `elm/html`'s `sup`.
-}
sup : List Attribute -> List Html -> Html
sup =
    node "sup"


{-| Same as `elm/html`'s `input`.
-}
input : List Attribute -> List Html -> Html
input =
    node "input"


{-| Same as `elm/html`'s `time`.
-}
time : List Attribute -> List Html -> Html
time =
    node "time"


{-| Same as `elm/html`'s `figure`.
-}
figure : List Attribute -> List Html -> Html
figure =
    node "figure"


{-| Same as `elm/html`'s `figcaption`.
-}
figcaption : List Attribute -> List Html -> Html
figcaption =
    node "figcaption"


{-| Same as `elm/html`'s `small`.
-}
small : List Attribute -> List Html -> Html
small =
    node "small"
