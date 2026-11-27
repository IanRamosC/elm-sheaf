module Sheaf.Svg exposing
    ( Svg, Attribute
    , node
    , svg, g, path, circle, ellipse, line, polyline, polygon, rect
    , title, desc
    , defs, linearGradient, radialGradient, stop, clipPath, mask
    )

{-| Inline SVG that can be rendered to a string, with the names of `elm/svg`.

These elements go into the same tree as `Sheaf.Html`, so an icon can sit
anywhere in a template. `script` and `style` are refused here as they are
there.

    import Sheaf.Html as Html
    import Sheaf.Html.Attributes exposing (attribute)
    import Sheaf.Svg as Svg
    import Sheaf.Svg.Attributes as SvgA

    arrow : Html.Html
    arrow =
        Svg.svg
            [ SvgA.viewBox "0 0 24 24"
            , SvgA.width "24"
            , SvgA.height "24"
            , attribute "aria-hidden" "true"
            ]
            [ Svg.path [ SvgA.d "M5 12h14", SvgA.stroke "currentColor" ] [] ]

@docs Svg, Attribute
@docs node


# Shapes

@docs svg, g, path, circle, ellipse, line, polyline, polygon, rect


# Descriptions

@docs title, desc


# Gradients, clipping and masks

@docs defs, linearGradient, radialGradient, stop, clipPath, mask

-}

import Sheaf.Html as Html
import Sheaf.Internal.Html as Internal


{-| A piece of SVG. It is the same type as `Sheaf.Html.Html`.
-}
type alias Svg =
    Html.Html


{-| An attribute of an element. See `Sheaf.Svg.Attributes`.
-}
type alias Attribute =
    Html.Attribute


{-| An element with any tag name, like `node "feGaussianBlur"`.

A tag name that is not valid, or `script` and `style`, is reported when the
page is built.

-}
node : String -> List Attribute -> List Svg -> Svg
node =
    Internal.node


{-| The root of a drawing.
-}
svg : List Attribute -> List Svg -> Svg
svg =
    node "svg"


{-| A group of elements that share attributes.
-}
g : List Attribute -> List Svg -> Svg
g =
    node "g"


{-| A shape drawn from path commands.
-}
path : List Attribute -> List Svg -> Svg
path =
    node "path"


{-| A circle.
-}
circle : List Attribute -> List Svg -> Svg
circle =
    node "circle"


{-| An ellipse.
-}
ellipse : List Attribute -> List Svg -> Svg
ellipse =
    node "ellipse"


{-| A straight line.
-}
line : List Attribute -> List Svg -> Svg
line =
    node "line"


{-| Connected line segments.
-}
polyline : List Attribute -> List Svg -> Svg
polyline =
    node "polyline"


{-| A closed shape of straight segments.
-}
polygon : List Attribute -> List Svg -> Svg
polygon =
    node "polygon"


{-| A rectangle.
-}
rect : List Attribute -> List Svg -> Svg
rect =
    node "rect"


{-| A name for the enclosing element, read by assistive technology.
-}
title : List Attribute -> List Svg -> Svg
title =
    node "title"


{-| A longer description of the enclosing element.
-}
desc : List Attribute -> List Svg -> Svg
desc =
    node "desc"


{-| Elements that are drawn only when something else refers to them.
-}
defs : List Attribute -> List Svg -> Svg
defs =
    node "defs"


{-| A gradient along a line.
-}
linearGradient : List Attribute -> List Svg -> Svg
linearGradient =
    node "linearGradient"


{-| A gradient from a centre outwards.
-}
radialGradient : List Attribute -> List Svg -> Svg
radialGradient =
    node "radialGradient"


{-| A colour of a gradient.
-}
stop : List Attribute -> List Svg -> Svg
stop =
    node "stop"


{-| A shape that clips whatever refers to it.
-}
clipPath : List Attribute -> List Svg -> Svg
clipPath =
    node "clipPath"


{-| An image whose luminance hides part of whatever refers to it.
-}
mask : List Attribute -> List Svg -> Svg
mask =
    node "mask"
