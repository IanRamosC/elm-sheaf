module Sheaf.RoutesTest exposing (suite)

import Expect
import RenderFixtures exposing (PostMeta, Source, bodyAt, draft, error, headAt, page, paths, post, postMeta, postPage, posts, render, request, requestUnder, span, titles)
import Sheaf
import Sheaf.Collection as Collection
import Sheaf.Document exposing (Document)
import Sheaf.Head as Head
import Sheaf.Html as Html
import Sheaf.Internal.Protocol exposing (Diagnostic, Severity(..))
import Sheaf.Ref as Ref
import Sheaf.Route as Route exposing (Listing, Page, Route)
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Sheaf.Route"
        [ paginatedTests
        , allItemsTests
        , missingDateTests
        , notFoundTests
        , badRouteTests
        , repeatedLinkTests
        ]



-- THE SITE


dated : String -> String -> Source
dated slug isoDate =
    let
        source : Source
        source =
            post slug
    in
    { source | date = Just isoDate }


{-| Five posts, written a day apart, from `a` to `e`.
-}
fivePosts : List Source
fivePosts =
    [ dated "c" "2026-11-03"
    , dated "a" "2026-11-01"
    , dated "e" "2026-11-05"
    , dated "b" "2026-11-02"
    , dated "d" "2026-11-04"
    ]


{-| The slugs of the page's items, then where it is among the pages.
-}
listingPage : Listing PostMeta -> Page
listingPage { items, pagination } =
    page
        [ Html.text
            (String.join " | "
                [ slugs items
                , String.fromInt pagination.page ++ "/" ++ String.fromInt pagination.pages
                , Maybe.withDefault "-" pagination.previous
                , Maybe.withDefault "-" pagination.next
                ]
            )
        ]


slugs : List (Document PostMeta) -> String
slugs items =
    String.join " " (List.map .slug items)


paginated : Int -> Route
paginated perPage =
    Route.paginated "/" { perPage = perPage } posts listingPage



-- PAGINATED


paginatedTests : Test
paginatedTests =
    describe "paginated"
        [ test "page 1 is at the pattern, and page n under page/n/" <|
            \_ ->
                request [ "posts" ] fivePosts
                    |> render [ paginated 2 ]
                    |> paths
                    |> Expect.equal [ "index.html", "page/2/index.html", "page/3/index.html" ]
        , test "the newest post comes first, and each page knows its neighbours under the base path" <|
            \_ ->
                request [ "posts" ] fivePosts
                    |> render [ paginated 2 ]
                    |> Expect.all
                        [ bodyAt "index.html" >> Expect.equal (Just "e d | 1/3 | - | /blog/page/2/")
                        , bodyAt "page/2/index.html" >> Expect.equal (Just "c b | 2/3 | /blog/ | /blog/page/3/")
                        , bodyAt "page/3/index.html" >> Expect.equal (Just "a | 3/3 | /blog/page/2/ | -")
                        ]
        , test "page 2 points back to the pattern itself, never to page/1/" <|
            \_ ->
                requestUnder "/" [ "posts" ] fivePosts
                    |> render [ paginated 2 ]
                    |> bodyAt "page/2/index.html"
                    |> Expect.equal (Just "c b | 2/3 | / | /page/3/")
        , test "a pattern below the root puts its later pages under it" <|
            \_ ->
                request [ "posts" ] fivePosts
                    |> render [ Route.paginated "/archive/" { perPage = 4 } posts listingPage ]
                    |> Expect.all
                        [ paths >> Expect.equal [ "archive/index.html", "archive/page/2/index.html" ]
                        , bodyAt "archive/page/2/index.html" >> Expect.equal (Just "a | 2/2 | /blog/archive/ | -")
                        ]
        , test "posts of the same date are ordered by slug" <|
            \_ ->
                request [ "posts" ] [ dated "b" "2026-11-01", dated "c" "2026-11-02", dated "a" "2026-11-01" ]
                    |> render [ paginated 5 ]
                    |> bodyAt "index.html"
                    |> Expect.equal (Just "c a b | 1/1 | - | -")
        , test "a draft is not listed" <|
            \_ ->
                let
                    secret : Source
                    secret =
                        draft "secret"
                in
                request [ "posts" ] [ dated "a" "2026-11-01", { secret | date = Just "2026-11-02" } ]
                    |> render [ paginated 2 ]
                    |> bodyAt "index.html"
                    |> Expect.equal (Just "a | 1/1 | - | -")
        , test "an empty collection still gets its first page" <|
            \_ ->
                request [ "posts" ] []
                    |> render [ paginated 2 ]
                    |> Expect.all
                        [ paths >> Expect.equal [ "index.html" ]
                        , bodyAt "index.html" >> Expect.equal (Just " | 1/1 | - | -")
                        ]
        , test "a frontmatter problem is reported once, and the listing is not written" <|
            \_ ->
                let
                    untitled : Source
                    untitled =
                        dated "b" "2026-11-02"
                in
                request [ "posts" ] [ dated "a" "2026-11-01", { untitled | frontmatter = [] } ]
                    |> render [ paginated 1, Route.eachItem "/posts/:slug/" posts postPage ]
                    |> Expect.all
                        [ titles >> Expect.equal [ "MISSING FIELD" ]
                        , paths >> Expect.equal [ "posts/a/index.html" ]
                        ]
        , test "a collection used only by a listing route is used" <|
            \_ ->
                request [ "notes" ] []
                    |> render [ Route.paginated "/notes/" { perPage = 2 } (Collection.named "notes" postMeta) listingPage ]
                    |> .diagnostics
                    |> Expect.equal []
        , test "the documents of a collection without item pages are still rendered" <|
            \_ ->
                request [ "posts" ] [ dated "a" "2026-11-01" ]
                    |> render
                        [ Route.paginated "/"
                            { perPage = 2 }
                            posts
                            (\listing -> page (List.concatMap .body listing.items))
                        ]
                    |> bodyAt "index.html"
                    |> Expect.equal (Just "<p>Hi</p>")
        ]



-- ALL ITEMS


allItemsTests : Test
allItemsTests =
    describe "allItems"
        [ test "lists every post on one page, newest first" <|
            \_ ->
                request [ "posts" ] (draft "secret" :: fivePosts)
                    |> render [ Route.allItems "/archive/" posts (\items -> page [ Html.text (slugs items) ]) ]
                    |> Expect.all
                        [ paths >> Expect.equal [ "archive/index.html" ]
                        , bodyAt "archive/index.html" >> Expect.equal (Just "e d c b a")
                        ]
        ]



-- MISSING DATES


missingDateTests : Test
missingDateTests =
    let
        undated : Source
        undated =
            let
                source : Source
                source =
                    post "undated"
            in
            { source | positions = [ ( "", span 1 1 4 ) ] }
    in
    describe "missing dates"
        [ test "an undated post of a listed collection is reported once, at its frontmatter" <|
            \_ ->
                request [ "posts" ] [ dated "a" "2026-11-01", undated ]
                    |> render
                        [ paginated 2
                        , Route.allItems "/archive/" posts (\items -> page [ Html.text (slugs items) ])
                        , Route.eachItem "/posts/:slug/" posts postPage
                        ]
                    |> Expect.all
                        [ .diagnostics
                            >> Expect.equal
                                [ { severity = Error
                                  , title = "MISSING DATE"
                                  , message = "This document has no date, but `posts` is listed by date."
                                  , sourcePath = Just "content/posts/undated.md"
                                  , span = Just (span 1 1 4)
                                  , hint = Just "Add `date: YYYY-MM-DD` to its frontmatter, or start its file name with the date."
                                  }
                                ]
                        , paths >> Expect.equal [ "posts/a/index.html", "posts/undated/index.html" ]
                        ]
        , test "an undated draft is not reported" <|
            \_ ->
                request [ "posts" ] [ draft "secret" ]
                    |> render [ paginated 2 ]
                    |> .diagnostics
                    |> Expect.equal []
        , test "a collection that is not listed needs no dates" <|
            \_ ->
                request [ "posts" ] [ post "a" ]
                    |> render [ Route.eachItem "/posts/:slug/" posts postPage ]
                    |> .diagnostics
                    |> Expect.equal []
        ]



-- NOT FOUND


notFoundTests : Test
notFoundTests =
    describe "notFound"
        [ test "writes 404.html" <|
            \_ ->
                request [] []
                    |> render [ Route.notFound (page [ Html.text "Not found" ]) ]
                    |> Expect.all
                        [ paths >> Expect.equal [ "404.html" ]
                        , bodyAt "404.html" >> Expect.equal (Just "Not found")
                        ]
        , test "has no canonical URL, because it is served in place of any missing page" <|
            \_ ->
                request [] []
                    |> render [ Route.notFound { title = "Not found", head = [ Head.canonical ], body = [] } ]
                    |> headAt "404.html"
                    |> Maybe.map (String.contains "canonical")
                    |> Expect.equal (Just False)
        ]



-- BAD ROUTES


badRouteTests : Test
badRouteTests =
    let
        rejects : String -> Route -> String -> Test
        rejects description route problem =
            test description <|
                \_ ->
                    request [ "posts" ] [ dated "a" "2026-11-01" ]
                        |> render [ route, Route.eachItem "/posts/:slug/" posts postPage ]
                        |> Expect.all
                            [ titles >> Expect.equal [ "BAD ROUTE" ]
                            , .diagnostics >> List.map (.message >> String.contains problem) >> Expect.equal [ True ]
                            , paths >> Expect.equal [ "posts/a/index.html" ]
                            ]
    in
    describe "bad routes"
        [ rejects "a paginated pattern must be a folder"
            (Route.paginated "/notes" { perPage = 2 } posts listingPage)
            "The route `/notes` does not end with `/`"
        , rejects "a paginated pattern has no placeholder"
            (Route.paginated "/notes/:slug/" { perPage = 2 } posts listingPage)
            "has the placeholder `:slug`, which this kind of route does not fill"
        , rejects "a paginated route needs at least one item per page"
            (paginated 0)
            "`perPage` must be at least 1"
        , rejects "an item route needs :slug"
            (Route.eachItem "/posts/" posts postPage)
            "The route `/posts/` does not have the placeholder `:slug`"
        , rejects "a placeholder is a whole segment"
            (Route.eachItem "/x/:slugger/" posts postPage)
            "The route `/x/:slugger/` has the placeholder `:slugger`, which this kind of route does not fill"
        , rejects "a single page fills no placeholder"
            (Route.single "/x/:slug/" (page []))
            "The route `/x/:slug/` has the placeholder `:slug`, which this kind of route does not fill"
        , rejects "a route may not be in the folder of Sheaf's own files"
            (Route.single "/_sheaf/x/" (page []))
            "The route `/_sheaf/x/` is in `/_sheaf/`, which is reserved for files Sheaf writes"
        , rejects "a route may not be the folder of Sheaf's own files"
            (Route.single "/_sheaf/" (page []))
            "The route `/_sheaf/` is in `/_sheaf/`, which is reserved for files Sheaf writes"
        , rejects "a page of all items fills no placeholder"
            (Route.allItems "/x/:slug/" posts (\_ -> page []))
            "has the placeholder `:slug`"
        , rejects "a grouped route needs :group"
            (Route.groupedBy "/tags/" { by = .tags, perPage = Nothing } posts (\_ _ -> page []))
            "The route `/tags/` does not have the placeholder `:group`"
        , rejects "a paginated grouped route must be a folder"
            (Route.groupedBy "/tags/:group" { by = .tags, perPage = Just 2 } posts (\_ _ -> page []))
            "The route `/tags/:group` does not end with `/`"
        , rejects "a grouped route needs at least one item per page"
            (Route.groupedBy "/tags/:group/" { by = .tags, perPage = Just 0 } posts (\_ _ -> page []))
            "`perPage` must be at least 1"
        , rejects "a page of all groups fills no placeholder"
            (Route.allGroups "/tags/:group/" .tags posts (\_ -> page []))
            "has the placeholder `:group`"
        , test "says which routes fill a placeholder" <|
            \_ ->
                request [] []
                    |> render [ Route.single "/x/:group/" (page []) ]
                    |> .diagnostics
                    |> List.map .hint
                    |> Expect.equal [ Just "`Route.eachItem` fills `:slug` and `Route.groupedBy` fills `:group`, each in a segment of its own, as in `/posts/:slug/` or `/tags/:group/`." ]
        , test "says how a placeholder is written" <|
            \_ ->
                request [ "posts" ] []
                    |> render [ Route.eachItem "/posts/" posts postPage ]
                    |> .diagnostics
                    |> List.map .hint
                    |> Expect.equal [ Just "Put `:slug` in a segment of its own, as in `/posts/:slug/`." ]
        ]



-- REPEATED LINK PROBLEMS


repeatedLinkTests : Test
repeatedLinkTests =
    let
        linkingToDraft : Document PostMeta -> Page
        linkingToDraft _ =
            page [ Sheaf.link (Ref.fromId "posts/secret") [ Html.text "Secret" ] ]

        draftError : String -> Diagnostic
        draftError subject =
            { severity = Error
            , title = "LINK TO DRAFT"
            , message = subject ++ " a `Sheaf.link` points to `posts/secret`, which is not published in this build because it is a draft or dated in the future."
            , sourcePath = Nothing
            , span = Nothing
            , hint = Just "Publish it, or remove the link. Drafts and future-dated documents are only built by `sheaf dev` and `sheaf build --drafts`."
            }
    in
    describe "repeated link problems"
        [ test "a layout shared by three pages reports its bad link once" <|
            \_ ->
                request [ "posts" ] [ post "a", post "b", post "c", draft "secret" ]
                    |> render [ Route.eachItem "/posts/:slug/" posts linkingToDraft ]
                    |> Expect.all
                        [ .diagnostics >> Expect.equal [ draftError "While rendering 3 pages from the route `/posts/:slug/` (the first is `/posts/a/`)," ]
                        , paths >> Expect.equal []
                        ]
        , test "a page that links to the draft twice is one page" <|
            \_ ->
                request [ "posts" ] [ draft "secret" ]
                    |> render
                        [ Route.single "/" (page [ Sheaf.link (Ref.fromId "posts/secret") [], Sheaf.link (Ref.fromId "posts/secret") [] ])
                        , Route.eachItem "/posts/:slug/" posts postPage
                        ]
                    |> .diagnostics
                    |> Expect.equal [ draftError "While rendering `/` from the route `/`," ]
        , test "each route reports its own" <|
            \_ ->
                request [ "posts" ] [ post "a", draft "secret" ]
                    |> render
                        [ Route.eachItem "/posts/:slug/" posts linkingToDraft
                        , Route.eachItem "/archive/:slug/" posts linkingToDraft
                        ]
                    |> titles
                    |> Expect.equal [ "LINK TO DRAFT", "LINK TO DRAFT" ]
        , test "different problems on one route are reported apart" <|
            \_ ->
                request [ "posts" ] [ post "a", draft "secret" ]
                    |> render
                        [ Route.eachItem "/posts/:slug/"
                            posts
                            (\_ -> page [ Sheaf.link (Ref.fromId "posts/secret") [], Sheaf.link (Ref.fromId "posts/nowhere") [] ])
                        ]
                    |> .diagnostics
                    |> Expect.equal
                        [ draftError "While rendering `/posts/a/` from the route `/posts/:slug/`,"
                        , error "BROKEN LINK" "While rendering `/posts/a/` from the route `/posts/:slug/`, a `Sheaf.link` points to `posts/nowhere`, but there is no such document."
                        ]
        ]
