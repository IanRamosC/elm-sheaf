module Sheaf.ProtocolTest exposing (suite)

import Dict
import Expect
import Json.Decode as Decode
import ProtocolFixtures
import Sheaf.Internal.Protocol as Protocol exposing (BuildMode(..), Node(..), Severity(..))
import Test exposing (Test, describe, test)
import Time


suite : Test
suite =
    describe "Sheaf.Internal.Protocol"
        [ requestTests
        , responseTests
        ]


decodeRequest : String -> Result Decode.Error Protocol.Request
decodeRequest =
    Decode.decodeString Protocol.requestDecoder


span : Int -> Int -> Int -> Protocol.Span
span line startColumn endColumn =
    { start = { line = line, column = startColumn }
    , end = { line = line, column = endColumn }
    }


requestTests : Test
requestTests =
    describe "requestDecoder"
        [ test "decodes the build settings" <|
            \_ ->
                decodeRequest ProtocolFixtures.minimalRequest
                    |> Result.map .build
                    |> Expect.equal
                        (Ok { siteUrl = "https://example.com", basePath = "/blog", mode = Production })
        , test "decodes a document's identity and dates" <|
            \_ ->
                decodeRequest ProtocolFixtures.minimalRequest
                    |> Result.map (.documents >> List.map (\document -> { id = document.id, slug = document.slug, date = document.date, updated = document.updated }))
                    |> Expect.equal
                        (Ok
                            [ { id = "posts/hello-world"
                              , slug = "hello-world"
                              , date = Just { posix = Time.millisToPosix 1767225600000, isoDate = "2026-01-01" }
                              , updated = Nothing
                              }
                            ]
                        )
        , test "decodes the build mode and the flags of a draft" <|
            \_ ->
                decodeRequest ProtocolFixtures.allNodesRequest
                    |> Result.map (\request -> ( request.build.mode, List.map (\document -> ( document.draft, document.excluded )) request.documents ))
                    |> Expect.equal (Ok ( Drafts, [ ( True, True ) ] ))
        , test "keeps the frontmatter as JSON and its field positions by path" <|
            \_ ->
                decodeRequest ProtocolFixtures.minimalRequest
                    |> Result.map
                        (\request ->
                            List.map
                                (\document ->
                                    ( Decode.decodeValue (Decode.field "title" Decode.string) document.frontmatter
                                    , Dict.get "title" document.frontmatterPositions
                                    , Dict.get "tags.1" document.frontmatterPositions
                                    )
                                )
                                request.documents
                        )
                    |> Expect.equal
                        (Ok
                            [ ( Ok "Hello"
                              , Just { key = Just (span 2 1 6), value = span 2 8 13 }
                              , Just { key = Nothing, value = span 3 11 12 }
                              )
                            ]
                        )
        , test "decodes every kind of node" <|
            \_ ->
                decodeRequest ProtocolFixtures.allNodesRequest
                    |> Result.map (.documents >> List.map (.tree >> nodeKinds))
                    |> Expect.equal
                        (Ok
                            [ [ "heading", "paragraph", "code", "code", "blockquote", "list", "list", "thematicBreak", "table", "footnoteDefinition" ] ]
                        )
        , test "rejects another protocol version" <|
            \_ ->
                ProtocolFixtures.minimalRequest
                    |> String.replace "\"protocolVersion\": 1" "\"protocolVersion\": 2"
                    |> decodeRequest
                    |> Result.mapError (always ())
                    |> Expect.equal (Err ())
        ]


nodeKinds : Node -> List String
nodeKinds node =
    case node of
        Root { children } ->
            List.map kind children

        _ ->
            []


kind : Node -> String
kind node =
    case node of
        Heading _ ->
            "heading"

        Paragraph _ ->
            "paragraph"

        Code _ ->
            "code"

        Blockquote _ ->
            "blockquote"

        ListBlock _ ->
            "list"

        ThematicBreak _ ->
            "thematicBreak"

        Table _ ->
            "table"

        FootnoteDefinition _ ->
            "footnoteDefinition"

        _ ->
            "other"


responseTests : Test
responseTests =
    describe "encodeResponse"
        [ test "produces the response fixture" <|
            \_ ->
                let
                    response : Protocol.Response
                    response =
                        { pages = [ { path = "posts/hello-world/index.html", html = "<p>Hello</p>" } ]
                        , diagnostics =
                            [ { severity = Error
                              , title = "Unresolved link"
                              , message = "posts/missing does not exist."
                              , sourcePath = Just "content/posts/hello-world.md"
                              , span = Just (span 7 3 20)
                              , hint = Just "Did you mean posts/hello-world?"
                              }
                            , { severity = Warning
                              , title = "Unused"
                              , message = "Nothing to see."
                              , sourcePath = Nothing
                              , span = Nothing
                              , hint = Nothing
                              }
                            ]
                        }
                in
                Decode.decodeString Decode.value ProtocolFixtures.responseWithDiagnostic
                    |> Result.map (Expect.equal (Protocol.encodeResponse response))
                    |> Result.withDefault (Expect.fail "the fixture is not JSON")
        ]
