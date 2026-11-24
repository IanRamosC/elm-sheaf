module Sheaf.Internal.Date exposing (Date(..), fromProtocol, toUtcTimestamp, compareNewestFirst)

{-| The date type behind [`Sheaf.Date`](Sheaf-Date), which other internal
modules can build and templates cannot.

@docs Date, fromProtocol, toUtcTimestamp, compareNewestFirst

-}

import Sheaf.Internal.Protocol as Protocol
import Time


{-| A moment, and the calendar date as the author wrote it.

The calendar parts are kept apart from the instant because the same instant is
a different day in different timezones, and `2026-11-30` is the 30th everywhere.

-}
type Date
    = Date Protocol.Date


{-| The decoder has already checked the ISO date, so this only wraps it.
-}
fromProtocol : Protocol.Date -> Date
fromProtocol =
    Date


{-| The instant in UTC, for the `<meta>` tags that want a timestamp.

    toUtcTimestamp date == "2026-11-30T08:00:00Z"

-}
toUtcTimestamp : Date -> String
toUtcTimestamp (Date { posix }) =
    String.concat
        [ pad 4 (Time.toYear Time.utc posix)
        , "-"
        , pad 2 (monthNumber (Time.toMonth Time.utc posix))
        , "-"
        , pad 2 (Time.toDay Time.utc posix)
        , "T"
        , pad 2 (Time.toHour Time.utc posix)
        , ":"
        , pad 2 (Time.toMinute Time.utc posix)
        , ":"
        , pad 2 (Time.toSecond Time.utc posix)
        , "Z"
        ]


{-| For `List.sortWith`, so the latest post comes first.
-}
compareNewestFirst : Date -> Date -> Order
compareNewestFirst (Date a) (Date b) =
    compare (Time.posixToMillis b.posix) (Time.posixToMillis a.posix)


pad : Int -> Int -> String
pad width number =
    String.padLeft width '0' (String.fromInt number)


monthNumber : Time.Month -> Int
monthNumber month =
    case month of
        Time.Jan ->
            1

        Time.Feb ->
            2

        Time.Mar ->
            3

        Time.Apr ->
            4

        Time.May ->
            5

        Time.Jun ->
            6

        Time.Jul ->
            7

        Time.Aug ->
            8

        Time.Sep ->
            9

        Time.Oct ->
            10

        Time.Nov ->
            11

        Time.Dec ->
            12
