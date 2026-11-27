module Sheaf.Svg.Attributes exposing
    ( viewBox, width, height
    , x, y, cx, cy, r, rx, ry, x1, y1, x2, y2, d, points, transform
    , fill, fillOpacity, fillRule, clipRule, clipPath, mask
    , stroke, strokeWidth, strokeLinecap, strokeLinejoin, strokeDasharray, strokeOpacity
    , opacity, offset, stopColor, stopOpacity, gradientUnits
    , id, class
    )

{-| Attributes for `Sheaf.Svg`, with the names of `elm/svg`.

Every value is a `String`, so a size is `width "24"`, unlike
`Sheaf.Html.Attributes.width`, which takes an `Int`. Use
`Sheaf.Html.Attributes.attribute` for any attribute not listed here.


# Size and position

@docs viewBox, width, height
@docs x, y, cx, cy, r, rx, ry, x1, y1, x2, y2, d, points, transform


# Paint

@docs fill, fillOpacity, fillRule, clipRule, clipPath, mask
@docs stroke, strokeWidth, strokeLinecap, strokeLinejoin, strokeDasharray, strokeOpacity
@docs opacity, offset, stopColor, stopOpacity, gradientUnits


# Identity

@docs id, class

-}

import Sheaf.Html exposing (Attribute)
import Sheaf.Internal.Html as Internal


{-| The position and size of the drawing, like `"0 0 24 24"`.
-}
viewBox : String -> Attribute
viewBox =
    Internal.attribute "viewBox"


{-| A width, like `"24"`.
-}
width : String -> Attribute
width =
    Internal.attribute "width"


{-| A height, like `"24"`.
-}
height : String -> Attribute
height =
    Internal.attribute "height"


{-| The horizontal position.
-}
x : String -> Attribute
x =
    Internal.attribute "x"


{-| The vertical position.
-}
y : String -> Attribute
y =
    Internal.attribute "y"


{-| The horizontal centre.
-}
cx : String -> Attribute
cx =
    Internal.attribute "cx"


{-| The vertical centre.
-}
cy : String -> Attribute
cy =
    Internal.attribute "cy"


{-| The radius.
-}
r : String -> Attribute
r =
    Internal.attribute "r"


{-| The horizontal radius, or the corner radius of a `rect`.
-}
rx : String -> Attribute
rx =
    Internal.attribute "rx"


{-| The vertical radius, or the corner radius of a `rect`.
-}
ry : String -> Attribute
ry =
    Internal.attribute "ry"


{-| The horizontal start of a `line`.
-}
x1 : String -> Attribute
x1 =
    Internal.attribute "x1"


{-| The vertical start of a `line`.
-}
y1 : String -> Attribute
y1 =
    Internal.attribute "y1"


{-| The horizontal end of a `line`.
-}
x2 : String -> Attribute
x2 =
    Internal.attribute "x2"


{-| The vertical end of a `line`.
-}
y2 : String -> Attribute
y2 =
    Internal.attribute "y2"


{-| The commands of a `path`, like `"M0 0h24"`.
-}
d : String -> Attribute
d =
    Internal.attribute "d"


{-| The points of a `polyline` or `polygon`.
-}
points : String -> Attribute
points =
    Internal.attribute "points"


{-| A transformation, like `"rotate(45)"`.
-}
transform : String -> Attribute
transform =
    Internal.attribute "transform"


{-| The colour inside a shape.
-}
fill : String -> Attribute
fill =
    Internal.attribute "fill"


{-| The opacity of the fill, from `"0"` to `"1"`.
-}
fillOpacity : String -> Attribute
fillOpacity =
    Internal.attribute "fill-opacity"


{-| How the inside of a shape is found, `"nonzero"` or `"evenodd"`.
-}
fillRule : String -> Attribute
fillRule =
    Internal.attribute "fill-rule"


{-| How the inside of a clipping shape is found.
-}
clipRule : String -> Attribute
clipRule =
    Internal.attribute "clip-rule"


{-| The clipping path to apply, like `"url(#clip)"`.
-}
clipPath : String -> Attribute
clipPath =
    Internal.attribute "clip-path"


{-| The mask to apply, like `"url(#fade)"`.
-}
mask : String -> Attribute
mask =
    Internal.attribute "mask"


{-| The colour of the outline.
-}
stroke : String -> Attribute
stroke =
    Internal.attribute "stroke"


{-| The width of the outline.
-}
strokeWidth : String -> Attribute
strokeWidth =
    Internal.attribute "stroke-width"


{-| The ends of an open outline: `"butt"`, `"round"` or `"square"`.
-}
strokeLinecap : String -> Attribute
strokeLinecap =
    Internal.attribute "stroke-linecap"


{-| The corners of an outline: `"miter"`, `"round"` or `"bevel"`.
-}
strokeLinejoin : String -> Attribute
strokeLinejoin =
    Internal.attribute "stroke-linejoin"


{-| The lengths of the dashes and gaps of an outline.
-}
strokeDasharray : String -> Attribute
strokeDasharray =
    Internal.attribute "stroke-dasharray"


{-| The opacity of the outline.
-}
strokeOpacity : String -> Attribute
strokeOpacity =
    Internal.attribute "stroke-opacity"


{-| The opacity of the whole element.
-}
opacity : String -> Attribute
opacity =
    Internal.attribute "opacity"


{-| Where a gradient `stop` sits along the gradient.
-}
offset : String -> Attribute
offset =
    Internal.attribute "offset"


{-| The colour of a gradient `stop`.
-}
stopColor : String -> Attribute
stopColor =
    Internal.attribute "stop-color"


{-| The opacity of a gradient `stop`.
-}
stopOpacity : String -> Attribute
stopOpacity =
    Internal.attribute "stop-opacity"


{-| The coordinate system of a gradient, `"userSpaceOnUse"` or `"objectBoundingBox"`.
-}
gradientUnits : String -> Attribute
gradientUnits =
    Internal.attribute "gradientUnits"


{-| A name for the element, so other elements can refer to it.
-}
id : String -> Attribute
id =
    Internal.attribute "id"


{-| The CSS classes of the element.
-}
class : String -> Attribute
class =
    Internal.attribute "class"
