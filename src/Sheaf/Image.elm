module Sheaf.Image exposing (Image, view, src, width, height, alt)

{-| Images that Sheaf has published, such as a document's cover image.

An image in `content/` or `static/` is published in several widths and
formats, so a browser downloads only what it needs. Sheaf reads its size from
the file, so the page does not move when it loads. A remote image is used as
it is, and has no size.

The cover image of a document comes from its `image` frontmatter key:

```yaml
image: cover.png
```

or, to describe it:

```yaml
image:
  src: cover.png
  alt: A lighthouse at dusk
```

@docs Image, view, src, width, height, alt

-}

import Sheaf.Html exposing (Attribute, Html)
import Sheaf.Internal.Image as Internal


{-| An image, as Sheaf found it when it built the site.
-}
type alias Image =
    Internal.Image


{-| The image, as Markdown images are shown.

    case post.image of
        Just cover ->
            Image.view [ class "cover" ] cover

        Nothing ->
            text ""

A local image becomes a `<picture>` that offers each file it was published
as, sized to fit the page up to its largest width. It loads lazily, when it
comes near the screen.

The attributes go on its `<img>`. One of them replaces Sheaf's attribute of
the same name, so an image at the top of the page can load at once:

    Image.view [ attribute "loading" "eager" ] cover

-}
view : List Attribute -> Image -> Html
view =
    Internal.view


{-| The URL of the image. For a local image, it is the path of its largest
file in its own format, from the root of the site, ready for
[`Head.openGraph`](Sheaf-Head#openGraph):

    Head.openGraph
        { title = post.meta.title
        , description = Nothing
        , image = Maybe.map Image.src post.image
        , kind = Head.Website
        }

A remote image keeps the URL it was given.

-}
src : Image -> String
src =
    Internal.src


{-| The width, in pixels, of the file that [`src`](#src) points to. A remote
image has no size, because Sheaf does not download it.

    Image.width cover == Just 1200

-}
width : Image -> Maybe Int
width =
    Internal.width


{-| The height, in pixels, of the file that [`src`](#src) points to. A remote
image has no size, because Sheaf does not download it.

    Image.height cover == Just 800

-}
height : Image -> Maybe Int
height =
    Internal.height


{-| The text that describes the image to someone who cannot see it, or `""`
when there is none.

    Image.alt cover == "A lighthouse at dusk"

-}
alt : Image -> String
alt =
    Internal.alt
