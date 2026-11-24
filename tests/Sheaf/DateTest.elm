module Sheaf.DateTest exposing (suite)

import Expect
import Sheaf.Date as Date exposing (Date)
import Sheaf.Internal.Date as Internal
import Test exposing (Test, describe, test)
import Time


suite : Test
suite =
    describe "Sheaf.Date"
        [ test "reads the calendar parts from the ISO date, not the instant" <|
            \_ ->
                -- The instant is still the 29th in UTC, but the author wrote the 30th.
                novemberThirtieth
                    |> (\parsed -> ( Date.year parsed, Date.month parsed, Date.day parsed ))
                    |> Expect.equal ( 2026, Time.Nov, 30 )
        , test "keeps the ISO date as written" <|
            \_ ->
                Date.toIsoDate novemberThirtieth
                    |> Expect.equal "2026-11-30"
        , test "keeps the instant" <|
            \_ ->
                Date.toPosix novemberThirtieth
                    |> Time.posixToMillis
                    |> Expect.equal 1795993200000
        , test "writes the instant as a UTC timestamp" <|
            \_ ->
                Internal.toUtcTimestamp novemberThirtieth
                    |> Expect.equal "2026-11-29T23:00:00Z"
        , test "orders the newest date first" <|
            \_ ->
                [ novemberThirtieth, earlier, later ]
                    |> List.sortWith Internal.compareNewestFirst
                    |> List.map Date.toIsoDate
                    |> Expect.equal [ "2026-12-01", "2026-11-30", "2026-11-01" ]
        ]


novemberThirtieth : Date
novemberThirtieth =
    dateOf 1795993200000 "2026-11-30" ( 2026, Time.Nov, 30 )


earlier : Date
earlier =
    dateOf 1793491200000 "2026-11-01" ( 2026, Time.Nov, 1 )


later : Date
later =
    dateOf 1796083200000 "2026-12-01" ( 2026, Time.Dec, 1 )


dateOf : Int -> String -> ( Int, Time.Month, Int ) -> Date
dateOf millis isoDate ( year, month, day ) =
    Internal.fromProtocol
        { posix = Time.millisToPosix millis
        , isoDate = isoDate
        , year = year
        , month = month
        , day = day
        }
