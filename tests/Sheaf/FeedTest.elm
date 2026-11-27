module Sheaf.FeedTest exposing (suite)

import Expect
import Json.Encode as Encode exposing (Value)
import RenderFixtures exposing (PostMeta, Source, bodyAt, containerDirective, draft, footnoteDefinition, footnoteReference, heading, image, imageWith, link, markdownLink, page, paragraph, paths, photo, post, postRoute, posts, renderWithFeeds, request, requestUnder, requestWithSlugs, span, textNode, titles)
import Sheaf
import Sheaf.Collection as Collection
import Sheaf.Component as Component exposing (Component)
import Sheaf.Feed as Feed exposing (Feed)
import Sheaf.Frontmatter as Frontmatter
import Sheaf.Head as Head
import Sheaf.Html as Html
import Sheaf.Internal.Protocol exposing (Diagnostic, FeedItem, Response, Severity(..), SitemapEntry)
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
        , groupedFeedTests
        , feedLinkTests
        , sitemapTests
        , clashTests
        ]



-- THE SITE


feedAt : { rss : String, atom : String } -> Feed
feedAt files =
    Feed.fromCollection { rss = files.rss, atom = files.atom, limit = Nothing } posts aboutPost


limitedTo : Maybe Int -> Feed
limitedTo limit =
    Feed.fromCollection { rss = "/feed.xml", atom = "/atom.xml", limit = limit } posts aboutPost


aboutPost : PostMeta -> { title : String, summary : Maybe String }
aboutPost meta =
    { title = meta.title, summary = Just ("About " ++ meta.title) }


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


thirdOfNovember : Time.Posix
thirdOfNovember =
    Time.millisToPosix 1793664000000


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
        , test "a limit keeps the newest items, so the feed was last updated when they were" <|
            \_ ->
                let
                    revised : Source
                    revised =
                        dated "a" "2026-11-01"
                in
                request [ "posts" ] [ { revised | updated = Just "2026-11-04" }, dated "b" "2026-11-02", dated "c" "2026-11-03" ]
                    |> renderWithFeeds [ postRoute ] [ limitedTo (Just 2) ]
                    |> items
                    |> List.map (\item -> ( item.documentId, item.updated ))
                    |> Expect.equal [ ( "posts/c", thirdOfNovember ), ( "posts/b", secondOfNovember ) ]
        , test "a limit counts published documents only" <|
            \_ ->
                let
                    newestDraft : Source
                    newestDraft =
                        draft "secret"
                in
                request [ "posts" ] [ dated "a" "2026-11-01", dated "b" "2026-11-02", { newestDraft | date = Just "2026-11-03" } ]
                    |> renderWithFeeds [ postRoute ] [ limitedTo (Just 2) ]
                    |> items
                    |> List.map .documentId
                    |> Expect.equal [ "posts/b", "posts/a" ]
        , test "no limit keeps every item" <|
            \_ ->
                request [ "posts" ] [ dated "a" "2026-11-01", dated "b" "2026-11-02", dated "c" "2026-11-03" ]
                    |> renderWithFeeds [ postRoute ] [ limitedTo Nothing ]
                    |> items
                    |> List.map .documentId
                    |> Expect.equal [ "posts/c", "posts/b", "posts/a" ]
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
        , test "a component's link to a document points to its page" <|
            \_ ->
                request [ "posts" ] [ dated "a" "2026-11-01" |> withBody [ seeAlso "posts/b" ], dated "b" "2026-11-01" ]
                    |> renderWithComponents
                    |> itemHtml
                    |> List.head
                    |> Expect.equal (Just "<aside><a href=\"https://example.com/blog/posts/b/\">See also</a><p>Hi</p></aside>")
        , test "a component's link to a draft is reported as on the item's page" <|
            \_ ->
                request [ "posts" ] [ dated "a" "2026-11-01" |> withBody [ seeAlso "posts/secret" ], draft "secret" ]
                    |> renderWithComponents
                    |> .diagnostics
                    |> List.map (\diagnostic -> ( diagnostic.title, diagnostic.message ))
                    |> Expect.equal
                        [ ( "LINK TO DRAFT", "While rendering `/posts/a/` from the route `/posts/:slug/`, a `Sheaf.link` points to `posts/secret`, which is not published in this build because it is a draft or dated in the future." ) ]
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
        , test "feeds leave the self-link out" <|
            \_ ->
                linkingTo [ heading 2 "setup" [ textNode "Setup" ], paragraph [ link "#setup" ] ]
                    |> Expect.all
                        [ itemHtml >> Expect.equal [ "<h2 id=\"setup\">Setup</h2><p><a href=\"https://example.com/blog/posts/a/#setup\">link</a></p>" ]
                        , bodyAt "posts/a/index.html"
                            >> Maybe.map (String.contains "<h2 id=\"setup\">Setup <a class=\"heading-link\" href=\"#setup\" aria-labelledby=\"setup\">#</a></h2>")
                            >> Expect.equal (Just True)
                        ]
        , test "the page keeps the URLs as written" <|
            \_ ->
                linkingTo [ paragraph [ link "../b/" ] ]
                    |> bodyAt "posts/a/index.html"
                    |> Expect.equal (Just "<article><h1>a</h1><p><a href=\"../b/\">link</a></p></article>")
        ]


{-| A container that links to the document named by its `to` attribute.
-}
seeAlsoComponent : Component
seeAlsoComponent =
    Component.container "see-also"
        (Component.succeed identity |> Component.required "to" Component.string)
        (\id children -> Html.aside [] (Sheaf.link (Ref.fromId id) [ Html.text "See also" ] :: children))


seeAlso : String -> Value
seeAlso id =
    containerDirective "see-also" [ ( "to", id ) ] (span 3 1 12) [ paragraph [ textNode "Hi" ] ]


renderWithComponents : Value -> Response
renderWithComponents =
    Render.render (Sheaf.site { metadata = RenderFixtures.metadata, routes = [ postRoute ], feeds = [ feed ], components = [ seeAlsoComponent ] })


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
        , test "a feed keeps at least one item" <|
            \_ ->
                request [ "posts" ] [ dated "a" "2026-11-01" ]
                    |> renderWithFeeds [ postRoute ] [ limitedTo (Just 0) ]
                    |> Expect.all
                        [ .diagnostics
                            >> Expect.equal
                                [ { severity = Sheaf.Internal.Protocol.Error
                                  , title = "BAD ROUTE"
                                  , message = "The feed `/feed.xml` has `limit = 0`, but `limit` must be at least 1, so it could not be written."
                                  , sourcePath = Nothing
                                  , span = Nothing
                                  , hint = Nothing
                                  }
                                ]
                        , .feeds >> Expect.equal []
                        ]
        , test "a document the feed cannot describe fails the build, naming the document" <|
            \_ ->
                let
                    summarized : Feed
                    summarized =
                        Feed.fromCollection { rss = "/feed.xml", atom = "/atom.xml", limit = Nothing }
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
        , test "a feed is titled after the site" <|
            \_ ->
                request [ "posts" ] [ dated "a" "2026-11-01" ]
                    |> renderWithFeeds [ postRoute ] [ feed ]
                    |> .feeds
                    |> List.map .title
                    |> Expect.equal [ "Example" ]
        , test "a feed of the whole collection is one file, so it fills no `:group`" <|
            \_ ->
                request [ "posts" ] [ dated "a" "2026-11-01" ]
                    |> renderWithFeeds [ postRoute ] [ feedAt { rss = "/tags/:group/feed.xml", atom = "/atom.xml" } ]
                    |> Expect.all
                        [ .diagnostics
                            >> List.map (\diagnostic -> ( diagnostic.message, diagnostic.hint ))
                            >> Expect.equal
                                [ ( "The RSS feed `/tags/:group/feed.xml` has the placeholder `:group`, but a feed is one file, so it could not be written."
                                  , Just "Name the file, as in `/feed.xml` or `/atom.xml`."
                                  )
                                ]
                        , .feeds >> Expect.equal []
                        ]
        , test "a feed orders its collection by date" <|
            \_ ->
                request [ "posts" ] [ post "undated" ]
                    |> renderWithFeeds [ postRoute ] [ feed ]
                    |> titles
                    |> Expect.equal [ "MISSING DATE" ]
        ]



-- A FEED FOR EACH GROUP


{-| A post with these tags, published on `isoDate`.
-}
tagged : String -> String -> List String -> Source
tagged slug isoDate tags =
    let
        source : Source
        source =
            dated slug isoDate
    in
    { source | frontmatter = ( "tags", Encode.list Encode.string tags ) :: source.frontmatter }


{-| What the host would send for the tags these tests use.
-}
tagRequest : List Source -> Value
tagRequest =
    requestWithSlugs
        [ ( "elm", "elm", "elm" )
        , ( "Elm", "elm", "elm" )
        , ( "css", "css", "css" )
        ]
        [ "posts" ]


groupedFeedAt : { rss : String, atom : String } -> Feed
groupedFeedAt files =
    Feed.groupedBy { rss = files.rss, atom = files.atom, limit = Nothing } { by = .tags } posts aboutPost


tagFeed : Feed
tagFeed =
    groupedFeedAt { rss = "/tags/:group/feed.xml", atom = "/tags/:group/atom.xml" }


writtenFeeds : Response -> List ( ( String, String ), String, List String )
writtenFeeds response =
    List.map (\written -> ( ( written.rss, written.atom ), written.title, List.map .documentId written.items )) response.feeds


badFeed : String -> Maybe String -> Diagnostic
badFeed message hint =
    { severity = Error
    , title = "BAD ROUTE"
    , message = message
    , sourcePath = Nothing
    , span = Nothing
    , hint = hint
    }


groupedFeedTests : Test
groupedFeedTests =
    describe "a feed for each group"
        [ test "each group has its own files, with its documents newest first, titled after the site and the group" <|
            \_ ->
                tagRequest [ tagged "a" "2026-11-01" [ "elm" ], tagged "b" "2026-11-02" [ "elm", "css" ], tagged "c" "2026-11-03" [] ]
                    |> renderWithFeeds [ postRoute ] [ tagFeed ]
                    |> writtenFeeds
                    |> Expect.equal
                        [ ( ( "tags/css/feed.xml", "tags/css/atom.xml" ), "Example · css", [ "posts/b" ] )
                        , ( ( "tags/elm/feed.xml", "tags/elm/atom.xml" ), "Example · elm", [ "posts/b", "posts/a" ] )
                        ]
        , test "a limit keeps the newest items of each group" <|
            \_ ->
                tagRequest [ tagged "a" "2026-11-01" [ "elm", "css" ], tagged "b" "2026-11-02" [ "elm" ] ]
                    |> renderWithFeeds [ postRoute ]
                        [ Feed.groupedBy { rss = "/tags/:group/feed.xml", atom = "/tags/:group/atom.xml", limit = Just 1 } { by = .tags } posts aboutPost ]
                    |> writtenFeeds
                    |> List.map (\( _, _, ids ) -> ids)
                    |> Expect.equal [ [ "posts/a" ], [ "posts/b" ] ]
        , test "spellings with one slug are one feed, named as the group's page is" <|
            \_ ->
                let
                    nameRoute : Route
                    nameRoute =
                        Route.groupedBy "/tags/:group/" { by = .tags, perPage = Nothing } posts (\name _ -> page [ Html.text name ])
                in
                tagRequest [ tagged "a" "2026-11-01" [ "Elm" ], tagged "b" "2026-11-02" [ "elm" ], tagged "c" "2026-11-03" [ "Elm" ] ]
                    |> renderWithFeeds [ postRoute, nameRoute ] [ tagFeed ]
                    |> Expect.all
                        [ writtenFeeds >> List.map (\( files, title, _ ) -> ( files, title )) >> Expect.equal [ ( ( "tags/elm/feed.xml", "tags/elm/atom.xml" ), "Example · Elm" ) ]
                        , bodyAt "tags/elm/index.html" >> Expect.equal (Just "Elm")
                        ]
        , test "a file without `:group` is reported, and no group's feed is written" <|
            \_ ->
                tagRequest [ tagged "a" "2026-11-01" [ "elm" ] ]
                    |> renderWithFeeds [ postRoute ] [ groupedFeedAt { rss = "/feed.xml", atom = "/tags/:group/atom.xml" } ]
                    |> Expect.all
                        [ .diagnostics
                            >> Expect.equal
                                [ badFeed "The RSS feed `/feed.xml` does not have the placeholder `:group`, which gives each group its own feed, so it could not be written."
                                    (Just "Put `:group` in a segment of its own, as in `/tags/:group/feed.xml`.")
                                ]
                        , .feeds >> Expect.equal []
                        ]
        , test "a file with `:group` twice is reported" <|
            \_ ->
                tagRequest [ tagged "a" "2026-11-01" [ "elm" ] ]
                    |> renderWithFeeds [ postRoute ] [ groupedFeedAt { rss = "/tags/:group/feed.xml", atom = "/:group/:group/atom.xml" } ]
                    |> Expect.all
                        [ .diagnostics
                            >> Expect.equal
                                [ badFeed "The Atom feed `/:group/:group/atom.xml` has the placeholder `:group` more than once, but each group's feed is one file, so it could not be written."
                                    (Just "Put `:group` in a segment of its own, as in `/tags/:group/feed.xml`.")
                                ]
                        , .feeds >> Expect.equal []
                        ]
        , test "a group's feed fills only `:group`" <|
            \_ ->
                tagRequest [ tagged "a" "2026-11-01" [ "elm" ] ]
                    |> renderWithFeeds [ postRoute ] [ groupedFeedAt { rss = "/tags/:group/:slug/feed.xml", atom = "/tags/:group/atom.xml" } ]
                    |> .diagnostics
                    |> Expect.equal
                        [ badFeed "The RSS feed `/tags/:group/:slug/feed.xml` has the placeholder `:slug`, which a feed for each group does not fill, so it could not be written."
                            (Just "`Feed.groupedBy` fills `:group`, in a segment of its own, as in `/tags/:group/feed.xml`.")
                        ]
        , test "a group's feed is a file" <|
            \_ ->
                tagRequest [ tagged "a" "2026-11-01" [ "elm" ] ]
                    |> renderWithFeeds [ postRoute ] [ groupedFeedAt { rss = "/tags/:group/", atom = "/tags/:group/atom.xml" } ]
                    |> .diagnostics
                    |> Expect.equal
                        [ badFeed "The RSS feed `/tags/:group/` ends with `/`, but a feed is a file, so it could not be written."
                            (Just "Name the file, as in `/tags/:group/feed.xml`.")
                        ]
        , test "a value with no slug is reported once by a route and a feed that group by it" <|
            \_ ->
                tagRequest [ tagged "a" "2026-11-01" [ "ELM" ] ]
                    |> renderWithFeeds [ postRoute, Route.groupedBy "/tags/:group/" { by = .tags, perPage = Nothing } posts (\name _ -> page [ Html.text name ]) ] [ tagFeed ]
                    |> Expect.all
                        [ .diagnostics
                            >> List.map (\diagnostic -> ( diagnostic.title, diagnostic.message ))
                            >> Expect.equal [ ( "MISSING SLUG", "The route `/tags/:group/` groups documents by the value `ELM`, which has no slug." ) ]
                        , .feeds >> Expect.equal []
                        ]
        , test "a feed names itself when it finds a value with no slug" <|
            \_ ->
                tagRequest [ tagged "a" "2026-11-01" [ "ELM" ] ]
                    |> renderWithFeeds [ postRoute ] [ tagFeed ]
                    |> .diagnostics
                    |> List.map (\diagnostic -> ( diagnostic.title, diagnostic.message ))
                    |> Expect.equal [ ( "MISSING SLUG", "The feed `/tags/:group/feed.xml` groups documents by the value `ELM`, which has no slug." ) ]
        , test "a group's feed file clashes like any other" <|
            \_ ->
                tagRequest [ tagged "a" "2026-11-01" [ "elm" ] ]
                    |> renderWithFeeds [ postRoute, Route.single "/tags/elm/feed.xml" (page []) ] [ tagFeed ]
                    |> .diagnostics
                    |> List.map (\diagnostic -> ( diagnostic.title, diagnostic.message ))
                    |> Expect.equal
                        [ ( "DUPLICATE PAGE", "The route `/tags/elm/feed.xml` and the RSS feed `/tags/elm/feed.xml` both make the file `tags/elm/feed.xml`." ) ]
        , test "the head can link to a group's feed, but not to a group with none" <|
            \_ ->
                tagRequest [ tagged "a" "2026-11-01" [ "elm" ] ]
                    |> renderWithFeeds
                        [ postRoute
                        , homeWithHead
                            [ Head.rssFeed { title = "Elm", path = "/tags/elm/feed.xml" }
                            , Head.atomFeed { title = "Elm", path = "/tags/elm/atom.xml" }
                            , Head.rssFeed { title = "Nope", path = "/tags/nope/feed.xml" }
                            ]
                        ]
                        [ tagFeed ]
                    |> .diagnostics
                    |> List.map (\diagnostic -> ( diagnostic.title, diagnostic.message ))
                    |> Expect.equal
                        [ ( "UNKNOWN FEED", "This page links to the RSS feed `/tags/nope/feed.xml`, but the site has no RSS feed at that path.\n\nFound while rendering `/` from the route `/`." ) ]
        , test "an unknown feed's hint names the feeds' patterns, not each group's file" <|
            \_ ->
                tagRequest [ tagged "a" "2026-11-01" [ "elm" ], tagged "b" "2026-11-02" [ "css" ] ]
                    |> renderWithFeeds [ postRoute, homeWithHead [ Head.rssFeed { title = "Posts", path = "/feeds.xml" } ] ] [ feed, tagFeed ]
                    |> .diagnostics
                    |> List.map .hint
                    |> Expect.equal [ Just "The RSS feeds of the site are `/feed.xml`, `/tags/:group/feed.xml`." ]
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



-- LINKS FROM THE HEAD


homeWithHead : List Head.Tag -> Route
homeWithHead head =
    Route.single "/" { title = "Home", head = head, body = [] }


feedLinkDiagnostics : List Head.Tag -> List Diagnostic
feedLinkDiagnostics head =
    request [ "posts" ] [ dated "a" "2026-11-01" ]
        |> renderWithFeeds [ postRoute, homeWithHead head ] [ feed ]
        |> .diagnostics
        |> List.filter (\diagnostic -> diagnostic.title == "UNKNOWN FEED")


feedLinkTests : Test
feedLinkTests =
    describe "links to feeds from the head"
        [ test "a feed the site does not write at that path is unknown" <|
            \_ ->
                feedLinkDiagnostics [ Head.rssFeed { title = "Posts", path = "/fed.xml" } ]
                    |> Expect.equal
                        [ { severity = Error
                          , title = "UNKNOWN FEED"
                          , message = "This page links to the RSS feed `/fed.xml`, but the site has no RSS feed at that path.\n\nFound while rendering `/` from the route `/`."
                          , sourcePath = Nothing
                          , span = Nothing
                          , hint = Just "The RSS feeds of the site are `/feed.xml`."
                          }
                        ]
        , test "an Atom link to the RSS file is unknown" <|
            \_ ->
                feedLinkDiagnostics [ Head.atomFeed { title = "Posts", path = "/feed.xml" } ]
                    |> List.map .message
                    |> Expect.equal
                        [ "This page links to the Atom feed `/feed.xml`, but the site has no Atom feed at that path.\n\nFound while rendering `/` from the route `/`." ]
        , test "links to the paths of the feed are fine, and so are feeds on other hosts" <|
            \_ ->
                feedLinkDiagnostics
                    [ Head.rssFeed { title = "Posts", path = "/feed.xml" }
                    , Head.atomFeed { title = "Posts", path = "/atom.xml" }
                    , Head.rssFeed { title = "Elsewhere", path = "https://example.org/rss.xml" }
                    ]
                    |> Expect.equal []
        , test "a layout shared by many pages is reported once, with their count" <|
            \_ ->
                let
                    route : Route
                    route =
                        Route.eachItem "/posts/:slug/"
                            posts
                            (\_ -> { title = "Post", head = [ Head.rssFeed { title = "Posts", path = "/fed.xml" } ], body = [] })
                in
                request [ "posts" ] [ dated "a" "2026-11-01", dated "b" "2026-11-02" ]
                    |> renderWithFeeds [ route ] [ feed ]
                    |> .diagnostics
                    |> List.map .message
                    |> Expect.equal
                        [ "These 2 pages link to the RSS feed `/fed.xml`, but the site has no RSS feed at that path.\n\nFound while rendering the pages of the route `/posts/:slug/`, the first of which is `/posts/a/`." ]
        ]
