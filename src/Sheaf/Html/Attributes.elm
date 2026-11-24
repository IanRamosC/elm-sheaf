module Sheaf.Html.Attributes exposing
    ( attribute
    , siteHref, siteSrc
    , class, id, href, src, alt, title, lang, rel, type_, name, content, charset, datetime
    , width, height
    , checked, disabled
    )

{-| Attributes for `Sheaf.Html`, with the names of `elm/html`.

@docs attribute


# Paths in the site

A site may be served from a base path, such as `/blog/` on
`https://example.com/blog/`. `siteHref` and `siteSrc` take a path from the
root of the site, starting with a single `/`, and the base path is put in front
when the page is built:

    a [ siteHref "/archive/" ] [ text "Archive" ]

renders `<a href="/blog/archive/">Archive</a>` under `/blog/`. Any other path
is reported when the page is built. Use `href` and `src` for URLs on other
hosts.

@docs siteHref, siteSrc


# Attributes

@docs class, id, href, src, alt, title, lang, rel, type_, name, content, charset, datetime
@docs width, height
@docs checked, disabled

-}

import Sheaf.Html exposing (Attribute)
import Sheaf.Internal.Html as Internal


{-| An attribute with any name, like `attribute "data-id" "7"`.

A name that is not valid is reported when the page is built.

-}
attribute : String -> String -> Attribute
attribute =
    Internal.attribute


{-| The `href` attribute, for a path from the root of the site such as
`/archive/`. It gets the base path in front.
-}
siteHref : String -> Attribute
siteHref =
    Internal.sitePathAttribute "href"


{-| The `src` attribute, for a path from the root of the site such as
`/cover.png`. It gets the base path in front.
-}
siteSrc : String -> Attribute
siteSrc =
    Internal.sitePathAttribute "src"


{-| The `class` attribute.
-}
class : String -> Attribute
class =
    Internal.attribute "class"


{-| The `id` attribute.
-}
id : String -> Attribute
id =
    Internal.attribute "id"


{-| The `href` attribute.
-}
href : String -> Attribute
href =
    Internal.attribute "href"


{-| The `src` attribute.
-}
src : String -> Attribute
src =
    Internal.attribute "src"


{-| The `alt` attribute.
-}
alt : String -> Attribute
alt =
    Internal.attribute "alt"


{-| The `title` attribute.
-}
title : String -> Attribute
title =
    Internal.attribute "title"


{-| The `lang` attribute.
-}
lang : String -> Attribute
lang =
    Internal.attribute "lang"


{-| The `rel` attribute.
-}
rel : String -> Attribute
rel =
    Internal.attribute "rel"


{-| The `type` attribute.
-}
type_ : String -> Attribute
type_ =
    Internal.attribute "type"


{-| The `name` attribute.
-}
name : String -> Attribute
name =
    Internal.attribute "name"


{-| The `content` attribute.
-}
content : String -> Attribute
content =
    Internal.attribute "content"


{-| The `charset` attribute.
-}
charset : String -> Attribute
charset =
    Internal.attribute "charset"


{-| The `datetime` attribute.
-}
datetime : String -> Attribute
datetime =
    Internal.attribute "datetime"


{-| The `width` attribute, in pixels.
-}
width : Int -> Attribute
width pixels =
    Internal.attribute "width" (String.fromInt pixels)


{-| The `height` attribute, in pixels.
-}
height : Int -> Attribute
height pixels =
    Internal.attribute "height" (String.fromInt pixels)


{-| The `checked` attribute, present when `True`.
-}
checked : Bool -> Attribute
checked =
    Internal.booleanAttribute "checked"


{-| The `disabled` attribute, present when `True`.
-}
disabled : Bool -> Attribute
disabled =
    Internal.booleanAttribute "disabled"
