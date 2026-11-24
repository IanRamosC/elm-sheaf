module Sheaf.Date exposing (Date, year, month, day, toIsoDate, toPosix)

{-| The date of a document.

The calendar parts come from the date as the author wrote it, so a post dated
`2026-11-30` shows the 30th in every timezone. [`toPosix`](#toPosix) is the
instant, for code that needs one.

@docs Date, year, month, day, toIsoDate, toPosix

-}

import Sheaf.Internal.Date as Internal
import Time


{-| A document's date.
-}
type alias Date =
    Internal.Date


{-| The year, as in `2026`.
-}
year : Date -> Int
year (Internal.Date date) =
    date.year


{-| The month, as in `Time.Nov`.
-}
month : Date -> Time.Month
month (Internal.Date date) =
    date.month


{-| The day of the month, from 1 to 31.
-}
day : Date -> Int
day (Internal.Date date) =
    date.day


{-| The calendar date as written, as in `"2026-11-30"`.
-}
toIsoDate : Date -> String
toIsoDate (Internal.Date date) =
    date.isoDate


{-| The instant the date stands for.
-}
toPosix : Date -> Time.Posix
toPosix (Internal.Date date) =
    date.posix
