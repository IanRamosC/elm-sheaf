module Sheaf.GroupTest exposing (suite)

import Expect
import Json.Encode as Encode
import RenderFixtures exposing (PostMeta, Source, bodyAt, page, paths, post, posts, render, requestWithSlugs, span, titles)
import Sheaf
import Sheaf.Document exposing (Document)
import Sheaf.Html as Html exposing (Html)
import Sheaf.Internal.Protocol exposing (Diagnostic, Severity(..))
import Sheaf.Route as Route exposing (Group, Listing, Page, Route)
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Grouped routes"
        [ groupedByTests
        , allGroupsTests
        , slugProblemTests
        , groupLinkTests
        ]



-- THE SITE


{-| A post with these tags, on day `day` of November 2026.
-}
tagged : String -> Int -> List String -> Source
tagged slug day tags =
    let
        source : Source
        source =
            post slug
    in
    { source
        | date = Just ("2026-11-" ++ String.padLeft 2 '0' (String.fromInt day))
        , frontmatter = ( "tags", Encode.list Encode.string tags ) :: source.frontmatter
    }


draftTagged : String -> Int -> List String -> Source
draftTagged slug day tags =
    let
        source : Source
        source =
            tagged slug day tags
    in
    { source | excluded = True }


{-| What the host would send for the values these tests use.
-}
slugTable : List ( String, String, String )
slugTable =
    [ ( "Elm", "elm", "elm" )
    , ( "elm", "elm", "elm" )
    , ( "Élm", "elm", "elm" )
    , ( "Tooling", "tooling", "tooling" )
    , ( "C", "c", "c" )
    , ( "C++", "c", "c++" )
    , ( "Secret", "secret", "secret" )
    , ( "日本", "日本", "日本" )
    , ( "hasOwnProperty", "hasownproperty", "hasownproperty" )
    , ( "open source", "open-source", "open source" )
    , ( "open-source", "open-source", "open source" )
    , ( "+++", "", "+++" )
    ]


request : List Source -> Encode.Value
request =
    requestWithSlugs slugTable [ "posts" ]


{-| The group's name, the slugs of the page's items, then where it is among
the pages.
-}
tagPage : String -> Listing PostMeta -> Page
tagPage name { items, pagination } =
    page
        [ Html.text
            (String.join " | "
                [ name
                , slugs items
                , String.fromInt pagination.page ++ "/" ++ String.fromInt pagination.pages
                , Maybe.withDefault "-" pagination.next
                ]
            )
        ]


slugs : List (Document PostMeta) -> String
slugs items =
    String.join " " (List.map .slug items)


tagRoute : Route
tagRoute =
    Route.groupedBy "/tags/:group/" { by = .tags, perPage = Nothing } posts tagPage


tagsPage : List (Group PostMeta) -> Page
tagsPage groups =
    page [ Html.text (String.join "; " (List.map (\group -> group.name ++ ": " ++ slugs group.items) groups)) ]


allTagsRoute : Route
allTagsRoute =
    Route.allGroups "/tags/" .tags posts tagsPage


home : List Html -> Route
home body =
    Route.single "/" (page body)



-- GROUPED BY


groupedByTests : Test
groupedByTests =
    describe "groupedBy"
        [ test "groups values by their slug, under the most common spelling, or the first by code point" <|
            \_ ->
                request [ tagged "a" 1 [ "Elm" ], tagged "b" 2 [ "elm", "Tooling" ], tagged "c" 3 [ "Élm" ] ]
                    |> render [ tagRoute ]
                    |> Expect.all
                        [ paths >> Expect.equal [ "tags/elm/index.html", "tags/tooling/index.html" ]
                        , bodyAt "tags/elm/index.html" >> Expect.equal (Just "Elm | c b a | 1/1 | -")
                        , bodyAt "tags/tooling/index.html" >> Expect.equal (Just "Tooling | b | 1/1 | -")
                        , .diagnostics >> Expect.equal []
                        ]
        , test "names a group by its most common spelling" <|
            \_ ->
                request [ tagged "a" 1 [ "elm" ], tagged "b" 2 [ "elm" ], tagged "c" 3 [ "Elm" ] ]
                    |> render [ tagRoute ]
                    |> bodyAt "tags/elm/index.html"
                    |> Expect.equal (Just "elm | c b a | 1/1 | -")
        , test "a value repeated in one document counts once" <|
            \_ ->
                request [ tagged "a" 1 [ "elm", "elm", "elm" ], tagged "b" 2 [ "Elm" ], tagged "c" 3 [ "Elm" ] ]
                    |> render [ tagRoute ]
                    |> bodyAt "tags/elm/index.html"
                    |> Expect.equal (Just "Elm | c b a | 1/1 | -")
        , test "a tag only on a draft has no page" <|
            \_ ->
                request [ tagged "a" 1 [ "Elm" ], draftTagged "secret" 2 [ "Secret" ] ]
                    |> render [ tagRoute ]
                    |> paths
                    |> Expect.equal [ "tags/elm/index.html" ]
        , test "a slug keeps its characters in the path and in links to it" <|
            \_ ->
                request [ tagged "a" 1 [ "日本" ] ]
                    |> render [ tagRoute, home [ Sheaf.groupLink "/tags/:group/" "日本" [ Html.text "Japan" ] ] ]
                    |> Expect.all
                        [ paths >> Expect.equal [ "tags/日本/index.html", "index.html" ]
                        , bodyAt "index.html" >> Expect.equal (Just "<a href=\"/blog/tags/日本/\">Japan</a>")
                        ]
        , test "a group's later pages are under its first" <|
            \_ ->
                request [ tagged "a" 1 [ "elm" ], tagged "b" 2 [ "elm" ] ]
                    |> render [ Route.groupedBy "/tags/:group/" { by = .tags, perPage = Just 1 } posts tagPage ]
                    |> Expect.all
                        [ paths >> Expect.equal [ "tags/elm/index.html", "tags/elm/page/2/index.html" ]
                        , bodyAt "tags/elm/index.html" >> Expect.equal (Just "elm | b | 1/2 | /blog/tags/elm/page/2/")
                        , bodyAt "tags/elm/page/2/index.html" >> Expect.equal (Just "elm | a | 2/2 | -")
                        ]
        , test "a tag named like an object property groups like any other" <|
            \_ ->
                request [ tagged "a" 1 [ "hasOwnProperty" ] ]
                    |> render [ tagRoute ]
                    |> Expect.all
                        [ paths >> Expect.equal [ "tags/hasownproperty/index.html" ]
                        , bodyAt "tags/hasownproperty/index.html" >> Expect.equal (Just "hasOwnProperty | a | 1/1 | -")
                        ]
        , test "an undated post keeps its groups from being written" <|
            \_ ->
                let
                    undated : Source
                    undated =
                        tagged "b" 2 [ "elm" ]
                in
                request [ tagged "a" 1 [ "elm" ], { undated | date = Nothing } ]
                    |> render [ tagRoute ]
                    |> Expect.all
                        [ titles >> Expect.equal [ "MISSING DATE" ]
                        , paths >> Expect.equal []
                        ]
        , test "a frontmatter problem is reported once, and no group is written" <|
            \_ ->
                let
                    untitled : Source
                    untitled =
                        tagged "b" 2 [ "elm" ]
                in
                request [ tagged "a" 1 [ "elm" ], { untitled | frontmatter = List.filter (\( key, _ ) -> key /= "title") untitled.frontmatter } ]
                    |> render [ tagRoute, allTagsRoute ]
                    |> Expect.all
                        [ titles >> Expect.equal [ "MISSING FIELD" ]
                        , paths >> Expect.equal []
                        ]
        , test "spellings that differ in spaces and dashes are one group" <|
            \_ ->
                request [ tagged "a" 1 [ "open source" ], tagged "b" 2 [ "open-source" ] ]
                    |> render [ tagRoute ]
                    |> Expect.all
                        [ paths >> Expect.equal [ "tags/open-source/index.html" ]
                        , .diagnostics >> Expect.equal []
                        ]
        ]



-- ALL GROUPS


allGroupsTests : Test
allGroupsTests =
    describe "allGroups"
        [ test "lists the groups by slug, each newest first" <|
            \_ ->
                request [ tagged "a" 1 [ "Tooling", "Elm" ], tagged "b" 2 [ "elm" ], draftTagged "secret" 3 [ "Secret" ] ]
                    |> render [ allTagsRoute ]
                    |> Expect.all
                        [ paths >> Expect.equal [ "tags/index.html" ]
                        , bodyAt "tags/index.html" >> Expect.equal (Just "Elm: b a; Tooling: a")
                        ]
        ]



-- SLUG PROBLEMS


collision : Diagnostic
collision =
    { severity = Error
    , title = "GROUP COLLISION"
    , message =
        "The values `C` and `C++` have the same slug, `c`, but are different words, so they cannot share a group:\n\n"
            ++ "    `C` in content/posts/a.md\n"
            ++ "    `C++` in content/posts/b.md"
    , sourcePath = Nothing
    , span = Nothing
    , hint = Just "Spell them the same way if they are the same thing, or rename one of them."
    }


slugProblemTests : Test
slugProblemTests =
    describe "slug problems"
        [ test "values with one slug but different words collide" <|
            \_ ->
                request [ tagged "a" 1 [ "C" ], tagged "b" 2 [ "C++" ] ]
                    |> render [ tagRoute ]
                    |> Expect.all
                        [ .diagnostics >> Expect.equal [ collision ]
                        , paths >> Expect.equal []
                        ]
        , test "a collision is reported once, however many routes group the values" <|
            \_ ->
                request [ tagged "a" 1 [ "C" ], tagged "b" 2 [ "C++" ] ]
                    |> render [ allTagsRoute, tagRoute ]
                    |> .diagnostics
                    |> Expect.equal [ collision ]
        , test "a value computed in Elm has no slug" <|
            \_ ->
                request [ tagged "a" 1 [ "elm" ], tagged "b" 2 [ "elm" ] ]
                    |> render
                        [ Route.groupedBy "/tags/:group/" { by = .tags >> List.map String.toUpper, perPage = Nothing } posts tagPage
                        , Route.allGroups "/tags/" (.tags >> List.map String.toUpper) posts tagsPage
                        ]
                    |> Expect.all
                        [ .diagnostics
                            >> Expect.equal
                                [ { severity = Error
                                  , title = "MISSING SLUG"
                                  , message = "The route `/tags/:group/` groups documents by the value `ELM`, which has no slug."
                                  , sourcePath = Nothing
                                  , span = Nothing
                                  , hint = Just "Group values must come from frontmatter as written; Sheaf computes their slugs before Elm runs."
                                  }
                                ]
                        , paths >> Expect.equal []
                        ]
        , test "a value with no letters or digits is reported where it is written" <|
            \_ ->
                let
                    source : Source
                    source =
                        tagged "a" 1 [ "elm", "+++" ]
                in
                request [ { source | positions = [ ( "", span 1 1 30 ), ( "tags.0", span 2 9 12 ), ( "tags.1", span 2 14 19 ) ] } ]
                    |> render [ tagRoute, allTagsRoute ]
                    |> Expect.all
                        [ .diagnostics
                            >> Expect.equal
                                [ { severity = Error
                                  , title = "EMPTY GROUP SLUG"
                                  , message = "The value `+++` has no letters or digits, so it has no slug to make a group page from."
                                  , sourcePath = Just "content/posts/a.md"
                                  , span = Just (span 2 14 19)
                                  , hint = Just "Use a value with at least one letter or digit, or remove it."
                                  }
                                ]
                        , paths >> Expect.equal []
                        ]
        ]



-- GROUP LINKS


linkError : String -> String -> Maybe String -> Diagnostic
linkError title message hint =
    { severity = Error
    , title = title
    , message = "While rendering `/` from the route `/`, a `Sheaf.groupLink` points to " ++ message
    , sourcePath = Nothing
    , span = Nothing
    , hint = hint
    }


groupLinkTests : Test
groupLinkTests =
    describe "groupLink"
        [ test "points to the group's page, whatever the spelling" <|
            \_ ->
                request [ tagged "a" 1 [ "elm" ] ]
                    |> render [ tagRoute, home [ Sheaf.groupLink "/tags/:group/" "Élm" [ Html.text "Elm" ] ] ]
                    |> bodyAt "index.html"
                    |> Expect.equal (Just "<a href=\"/blog/tags/elm/\">Elm</a>")
        , test "a group of drafts has no page to link to" <|
            \_ ->
                request [ tagged "a" 1 [ "elm" ], draftTagged "secret" 2 [ "Secret" ] ]
                    |> render [ tagRoute, home [ Sheaf.groupLink "/tags/:group/" "Secret" [] ] ]
                    |> Expect.all
                        [ .diagnostics
                            >> Expect.equal
                                [ linkError "LINK TO EMPTY GROUP"
                                    "the group `Secret` of `/tags/:group/`, but no published document is in it."
                                    (Just "Publish a document with this value, or remove the link. Drafts and future-dated documents are only built by `sheaf dev` and `sheaf build --drafts`.")
                                ]
                        , paths >> Expect.equal [ "tags/elm/index.html" ]
                        ]
        , test "needs a groupedBy route with the pattern" <|
            \_ ->
                request [ tagged "a" 1 [ "elm" ] ]
                    |> render [ tagRoute, home [ Sheaf.groupLink "/topics/:group/" "Elm" [] ] ]
                    |> .diagnostics
                    |> Expect.equal
                        [ linkError "NO PAGE FOR LINK"
                            "the group `Elm` of `/topics/:group/`, but no `Route.groupedBy` route has that pattern."
                            (Just "Did you mean `/tags/:group/`?")
                        ]
        , test "needs a value from frontmatter" <|
            \_ ->
                request [ tagged "a" 1 [ "elm" ] ]
                    |> render [ tagRoute, home [ Sheaf.groupLink "/tags/:group/" "ELM" [] ] ]
                    |> .diagnostics
                    |> Expect.equal
                        [ linkError "MISSING SLUG"
                            "the group `ELM` of `/tags/:group/`, but `ELM` has no slug."
                            (Just "Group values must come from frontmatter as written; Sheaf computes their slugs before Elm runs.")
                        ]
        , test "is reported with titles in the order found" <|
            \_ ->
                request [ tagged "a" 1 [ "elm" ] ]
                    |> render [ tagRoute, home [ Sheaf.groupLink "/topics/:group/" "Elm" [], Sheaf.groupLink "/tags/:group/" "ELM" [] ] ]
                    |> titles
                    |> Expect.equal [ "NO PAGE FOR LINK", "MISSING SLUG" ]
        ]
