module Sheaf.FeedTest exposing (suite)

import Expect
import Json.Encode exposing (Value)
import RenderFixtures exposing (Source, bodyAt, draft, footnoteDefinition, footnoteReference, image, imageWith, link, markdownLink, page, paragraph, paths, photo, post, postRoute, posts, renderWithFeeds, request, requestUnder, span, textNode, titles)
import Sheaf
import Sheaf.Collection as Collection
import Sheaf.Feed as Feed exposing (Feed)
import Sheaf.Frontmatter as Frontmatter
import Sheaf.Internal.Protocol exposing (FeedItem, Response, SitemapEntry)
import Sheaf.Internal.Render as Render
import Sheaf.Ref as Ref
import Sheaf.Route as Route exposing (Route)
import Test exposing (Test, describe, test)
import Time


suite : Test
suite =
    describe "Sheaf.Feed"
        [ itemTests
        , absoluteUrlTests
        , feedProblemTests
        , sitemapTests
        , clashTests
        ]



-- THE SITE


feedAt : { rss : String, atom : String } -> Feed
feedAt files =
    Feed.fromCollection files posts (\meta -> { title = meta.title, summary = Just ("About " ++ meta.title) })


feed : Feed
feed =
    feedAt { rss = "/feed.xml", atom = "/atom.xml" }


dated : String -> String -> Source
dated slug isoDate =
    let
        source : Source
        source =
            post slug
    in
    { source | date = Just isoDate }


withBody : List Value -> Source -> Source
withBody body source =
    { source | body = body }


{-| Midnight UTC on 1 and 2 November 2026.
-}
firstOfNovember : Time.Posix
firstOfNovember =
    Time.millisToPosix 1793491200000


secondOfNovember : Time.Posix
secondOfNovember =
    Time.millisToPosix 1793577600000


items : Response -> List FeedItem
items response =
    List.concatMap .items response.feeds


itemHtml : Response -> List String
itemHtml response =
    List.map .html (items response)



-- ITEMS


itemTests : Test
itemTests =
    describe "items"
        [ test "an item is a published document, with its page's absolute URL and links that point to their pages" <|
            \_ ->
                request [ "posts" ]
                    [ dated "a" "2026-11-01" |> withBody [ paragraph [ markdownLink "posts/b" (span 1 1 2) ] ]
                    , dated "b" "2026-11-01"
                    ]
                    |> renderWithFeeds [ postRoute ] [ feed ]
                    |> items
                    |> List.head
                    |> Expect.equal
                        (Just
                            { documentId = "posts/a"
                            , url = "https://example.com/blog/posts/a/"
                            , title = "a"
                            , summary = Just "About a"
                            , html = "<p><a href=\"https://example.com/blog/posts/b/\">link</a></p>"
                            , date = firstOfNovember
                            , updated = firstOfNovember
                            }
                        )
        , test "names its files without the leading slash, and lists the newest first, without drafts" <|
            \_ ->
                request [ "posts" ] [ dated "a" "2026-11-01", draft "secret", dated "b" "2026-11-02" ]
                    |> renderWithFeeds [ postRoute ] [ feed ]
                    |> .feeds
                    |> List.map (\written -> ( written.rss, written.atom, List.map .documentId written.items ))
                    |> Expect.equal [ ( "feed.xml", "atom.xml", [ "posts/b", "posts/a" ] ) ]
        , test "an item is updated when the author says, or else on its date" <|
            \_ ->
                let
                    revised : Source
                    revised =
                        dated "b" "2026-11-01"
                in
                request [ "posts" ] [ dated "a" "2026-11-01", { revised | updated = Just "2026-11-02" } ]
                    |> renderWithFeeds [ postRoute ] [ feed ]
                    |> items
                    |> List.map (\item -> ( item.documentId, item.updated ))
                    |> Expect.equal [ ( "posts/a", firstOfNovember ), ( "posts/b", secondOfNovember ) ]
        , test "Sheaf.withFeeds adds feeds after the site's own" <|
            \_ ->
                request [ "posts" ] [ dated "a" "2026-11-01" ]
                    |> Render.render
                        (Sheaf.site { metadata = RenderFixtures.metadata, routes = [ postRoute ], feeds = [ feed ], components = [] }
                            |> Sheaf.withFeeds [ feedAt { rss = "/posts.xml", atom = "/posts.atom" } ]
                        )
                    |> .feeds
                    |> List.map .rss
                    |> Expect.equal [ "feed.xml", "posts.xml" ]
        ]


absoluteUrlTests : Test
absoluteUrlTests =
    let
        linkingTo : List Value -> Response
        linkingTo body =
            request [ "posts" ] [ dated "a" "2026-11-01" |> withBody body ]
                |> renderWithFeeds [ postRoute ] [ feed ]

        becomes : String -> String -> Test
        becomes url absolute =
            test ("`" ++ url ++ "` becomes `" ++ absolute ++ "`") <|
                \_ ->
                    linkingTo [ paragraph [ link url ] ]
                        |> itemHtml
                        |> Expect.equal [ "<p><a href=\"" ++ absolute ++ "\">link</a></p>" ]
    in
    describe "absolute URLs in feeds"
        [ becomes "/about/" "https://example.com/about/"
        , becomes "//cdn.example.com/x" "https://cdn.example.com/x"
        , becomes "../b/" "https://example.com/blog/posts/b/"
        , becomes "../../../../x" "https://example.com/x"
        , becomes "./c/./d/.." "https://example.com/blog/posts/a/c/"
        , becomes "?q=1" "https://example.com/blog/posts/a/?q=1"
        , becomes "#top" "https://example.com/blog/posts/a/#top"
        , becomes "x/../y?a=../b#c" "https://example.com/blog/posts/a/y?a=../b#c"
        , becomes "mailto:a@b.c" "mailto:a@b.c"
        , becomes "https://elm-lang.org/../x" "https://elm-lang.org/../x"
        , test "an image's source is absolute" <|
            \_ ->
                linkingTo [ paragraph [ image "x.png" ] ]
                    |> itemHtml
                    |> Expect.equal [ "<p><img src=\"https://example.com/blog/posts/a/x.png\" alt=\"\" loading=\"lazy\" decoding=\"async\"></p>" ]
        , test "a local image's source and every candidate of its srcsets are absolute" <|
            \_ ->
                let
                    srcset : String -> String
                    srcset extension =
                        [ 480, 960, 1200 ]
                            |> List.map (\width -> "https://example.com/blog/_sheaf/images/h-" ++ String.fromInt width ++ "." ++ extension ++ " " ++ String.fromInt width ++ "w")
                            |> String.join ", "
                in
                linkingTo [ paragraph [ imageWith { url = "photo.png", alt = "", title = Nothing, local = Just photo } ] ]
                    |> itemHtml
                    |> List.map
                        (\html ->
                            List.map (\part -> String.contains part html)
                                [ "<source type=\"image/webp\" srcset=\"" ++ srcset "webp" ++ "\""
                                , "<img src=\"https://example.com/blog/_sheaf/images/h-1200.png\" srcset=\"" ++ srcset "png" ++ "\""
                                ]
                        )
                    |> Expect.equal [ [ True, True ] ]
        , test "a footnote reference points into the item's page" <|
            \_ ->
                linkingTo [ paragraph [ textNode "Hi", footnoteReference "1" ], footnoteDefinition "1" "Note." ]
                    |> itemHtml
                    |> List.map (String.contains "href=\"https://example.com/blog/posts/a/#user-content-fn-1\"")
                    |> Expect.equal [ True ]
        , test "the page keeps the URLs as written" <|
            \_ ->
                linkingTo [ paragraph [ link "../b/" ] ]
                    |> bodyAt "posts/a/index.html"
                    |> Expect.equal (Just "<article><h1>a</h1><p><a href=\"../b/\">link</a></p></article>")
        ]


feedProblemTests : Test
feedProblemTests =
    describe "feed problems"
        [ test "a feed over a collection with no item route has no URLs for its items" <|
            \_ ->
                request [ "posts" ] [ dated "a" "2026-11-01" ]
                    |> renderWithFeeds [] [ feed ]
                    |> Expect.all
                        [ .diagnostics
                            >> Expect.equal
                                [ { severity = Sheaf.Internal.Protocol.Error
                                  , title = "NO PAGE FOR FEED"
                                  , message = "The feed `/feed.xml` lists `posts`, but no route gives the documents of `posts` a page for its items to link to."
                                  , sourcePath = Nothing
                                  , span = Nothing
                                  , hint = Just "Add a `Route.eachItem` route for the `posts` collection."
                                  }
                                ]
                        , .feeds >> Expect.equal []
                        ]
        , test "a feed's file cannot be a folder" <|
            \_ ->
                request [ "posts" ] [ dated "a" "2026-11-01" ]
                    |> renderWithFeeds [ postRoute ] [ feedAt { rss = "/feed/", atom = "/atom.xml" } ]
                    |> Expect.all
                        [ .diagnostics
                            >> Expect.equal
                                [ { severity = Sheaf.Internal.Protocol.Error
                                  , title = "BAD ROUTE"
                                  , message = "The RSS feed `/feed/` ends with `/`, but a feed is a file, so it could not be written."
                                  , sourcePath = Nothing
                                  , span = Nothing
                                  , hint = Just "Name the file, as in `/feed.xml` or `/atom.xml`."
                                  }
                                ]
                        , .feeds >> Expect.equal []
                        ]
        , test "a feed's file is checked like a route's pattern" <|
            \_ ->
                request [ "posts" ] []
                    |> renderWithFeeds [ postRoute ] [ feedAt { rss = "/feed.xml", atom = "atom.xml" } ]
                    |> .diagnostics
                    |> List.map .message
                    |> Expect.equal [ "The Atom feed `atom.xml` does not start with `/`, so it could not be written." ]
        , test "a document the feed cannot describe fails the build, naming the document" <|
            \_ ->
                let
                    summarized : Feed
                    summarized =
                        Feed.fromCollection { rss = "/feed.xml", atom = "/atom.xml" }
                            (Collection.named "posts"
                                (Frontmatter.succeed (\title summary -> { title = title, summary = Just summary })
                                    |> Frontmatter.required "title" Frontmatter.string
                                    |> Frontmatter.required "summary" Frontmatter.string
                                )
                            )
                            identity
                in
                request [ "posts" ] [ dated "a" "2026-11-01" ]
                    |> renderWithFeeds [ postRoute ] [ summarized ]
                    |> Expect.all
                        [ .diagnostics >> List.map (\diagnostic -> ( diagnostic.title, diagnostic.sourcePath )) >> Expect.equal [ ( "MISSING FIELD", Just "content/posts/a.md" ) ]
                        , .feeds >> Expect.equal []
                        ]
        , test "a problem the feed and an item route both find is reported once" <|
            \_ ->
                let
                    untitled : Source
                    untitled =
                        dated "a" "2026-11-01"
                in
                request [ "posts" ] [ { untitled | frontmatter = [] } ]
                    |> renderWithFeeds [ postRoute ] [ feed ]
                    |> titles
                    |> Expect.equal [ "MISSING FIELD" ]
        , test "a feed orders its collection by date" <|
            \_ ->
                request [ "posts" ] [ post "undated" ]
                    |> renderWithFeeds [ postRoute ] [ feed ]
                    |> titles
                    |> Expect.equal [ "MISSING DATE" ]
        ]



-- THE SITEMAP


sitemapTests : Test
sitemapTests =
    let
        sitemapOf : List Route -> List Source -> List SitemapEntry
        sitemapOf routes sources =
            request [ "posts" ] sources
                |> renderWithFeeds routes []
                |> .sitemap
    in
    describe "the sitemap"
        [ test "lists every HTML page but the 404 page, with the base path, in page order" <|
            \_ ->
                sitemapOf
                    [ Route.single "/" (page [])
                    , Route.notFound (page [])
                    , Route.single "/humans.txt" (page [])
                    , Route.single "/colophon.html" (page [])
                    , postRoute
                    ]
                    [ post "a" ]
                    |> Expect.equal
                        [ { url = "https://example.com/blog/", lastModified = Nothing }
                        , { url = "https://example.com/blog/colophon.html", lastModified = Nothing }
                        , { url = "https://example.com/blog/posts/a/", lastModified = Nothing }
                        ]
        , test "an item's page was last modified when the document was updated" <|
            \_ ->
                let
                    revised : Source
                    revised =
                        dated "b" "2026-11-01"
                in
                sitemapOf [ postRoute ] [ dated "a" "2026-11-01", { revised | updated = Just "2026-11-02" } ]
                    |> List.map .lastModified
                    |> Expect.equal [ Just firstOfNovember, Just secondOfNovember ]
        , test "a site at the root has no base path in its URLs" <|
            \_ ->
                requestUnder "/" [ "posts" ] [ post "a" ]
                    |> renderWithFeeds [ postRoute ] []
                    |> .sitemap
                    |> List.map .url
                    |> Expect.equal [ "https://example.com/posts/a/" ]
        , test "a page that is not written is not listed" <|
            \_ ->
                sitemapOf [ Route.single "/" (page [ Sheaf.link (Ref.fromId "posts/nowhere") [] ]), postRoute ] []
                    |> Expect.equal []
        ]



-- CLASHING FILES


clashTests : Test
clashTests =
    let
        clashes : List Route -> List Feed -> List ( String, String, Maybe String )
        clashes routes feeds =
            request [ "posts" ] []
                |> renderWithFeeds (routes ++ [ postRoute ]) feeds
                |> .diagnostics
                |> List.map (\diagnostic -> ( diagnostic.title, diagnostic.message, diagnostic.hint ))

        caseHint : Maybe String
        caseHint =
            Just "Paths that differ only in case are one file on a disk that ignores case, as macOS's does."
    in
    describe "clashing files"
        [ test "pages that differ only in case clash" <|
            \_ ->
                clashes [ Route.single "/Archive/" (page []), Route.single "/archive/" (page []) ] []
                    |> Expect.equal
                        [ ( "DUPLICATE PAGE", "The routes `/Archive/` and `/archive/` make the pages `Archive/index.html` and `archive/index.html`.", caseHint ) ]
        , test "a page that is the folder of another clashes with it" <|
            \_ ->
                clashes [ Route.single "/about" (page []), Route.single "/about/" (page []) ] []
                    |> Expect.equal
                        [ ( "DUPLICATE PAGE", "The route `/about` makes the file `about`, but the route `/about/` makes `about/index.html`, which needs a folder of that name.", Nothing ) ]
        , test "a feed clashes with a page in a folder of its name" <|
            \_ ->
                clashes [ Route.single "/feed.xml/" (page []) ] [ feed ]
                    |> Expect.equal
                        [ ( "DUPLICATE PAGE", "The RSS feed `/feed.xml` makes the file `feed.xml`, but the route `/feed.xml/` makes `feed.xml/index.html`, which needs a folder of that name.", Nothing ) ]
        , test "a page clashes with the sitemap" <|
            \_ ->
                clashes [ Route.single "/sitemap.xml" (page []) ] []
                    |> Expect.equal
                        [ ( "DUPLICATE PAGE", "The route `/sitemap.xml` and the sitemap `/sitemap.xml` both make the file `sitemap.xml`.", Nothing ) ]
        , test "the first of two clashing pages is written" <|
            \_ ->
                request [ "posts" ] []
                    |> renderWithFeeds [ Route.single "/About/" (page []), Route.single "/about/" (page []) ] []
                    |> paths
                    |> Expect.equal [ "About/index.html" ]
        , test "a feed's two files clash" <|
            \_ ->
                clashes [] [ feedAt { rss = "/feed.xml", atom = "/Feed.xml" } ]
                    |> List.map (\( title, message, _ ) -> ( title, message ))
                    |> Expect.equal
                        [ ( "DUPLICATE PAGE", "The RSS feed `/feed.xml` and the Atom feed `/Feed.xml` make the files `feed.xml` and `Feed.xml`." ) ]
        ]
