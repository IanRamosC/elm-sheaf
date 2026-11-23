module SmokeTest exposing (suite)

import Expect
import Test exposing (Test, test)


suite : Test
suite =
    test "the toolchain runs tests" <|
        \_ -> Expect.equal 2 (1 + 1)
