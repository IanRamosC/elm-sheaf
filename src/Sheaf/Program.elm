module Sheaf.Program exposing (Model, Msg, worker)

{-| The program the host runs. The host generates the module that calls
[`worker`](#worker), so a site never uses this module itself.

@docs Model, Msg, worker

-}

import Json.Decode
import Json.Encode
import Sheaf exposing (Site)
import Sheaf.Internal.Protocol as Protocol
import Sheaf.Internal.Render as Render


{-| Whether the site has been built yet.
-}
type Model
    = Waiting
    | Responded


{-| The host's request.
-}
type Msg
    = Requested Json.Decode.Value


{-| A worker that waits for the host's request on `request`, builds every page
of the site, and sends the pages and any problems back on `respond`, once.
-}
worker :
    { request : (Json.Decode.Value -> Msg) -> Sub Msg
    , respond : Json.Encode.Value -> Cmd Msg
    }
    -> Site
    -> Program () Model Msg
worker ports site =
    Platform.worker
        { init = \_ -> ( Waiting, Cmd.none )
        , update =
            \(Requested request) _ ->
                ( Responded, ports.respond (Protocol.encodeResponse (Render.render site request)) )
        , subscriptions =
            \model ->
                case model of
                    Waiting ->
                        ports.request Requested

                    Responded ->
                        Sub.none
        }
