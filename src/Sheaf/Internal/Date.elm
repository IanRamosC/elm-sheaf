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
    = Date
        { posix : Time.Posix
        , isoDate : String
        , year : Int
        , month : Time.Month
        , day : Int
        }


{-| Read the calendar parts from the ISO date the host sends.

The host only sends dates that are valid, so the instant is the fallback only
to keep this total.

-}
fromProtocol : Protocol.Date -> Date
fromProtocol { posix, isoDate } =
    case List.map String.toInt (String.split "-" isoDate) of
        [ Just year, Just month, Just day ] ->
            Date { posix = posix, isoDate = isoDate, year = year, month = monthFromNumber month, day = day }

        _ ->
            Date
                { posix = posix
                , isoDate = isoDate
                , year = Time.toYear Time.utc posix
                , month = Time.toMonth Time.utc posix
                , day = Time.toDay Time.utc posix
                }


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


monthFromNumber : Int -> Time.Month
monthFromNumber number =
    case number of
        1 ->
            Time.Jan

        2 ->
            Time.Feb

        3 ->
            Time.Mar

        4 ->
            Time.Apr

        5 ->
            Time.May

        6 ->
            Time.Jun

        7 ->
            Time.Jul

        8 ->
            Time.Aug

        9 ->
            Time.Sep

        10 ->
            Time.Oct

        11 ->
            Time.Nov

        _ ->
            Time.Dec


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
