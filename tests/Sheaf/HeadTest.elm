module Sheaf.HeadTest exposing (suite)

import Expect
import Sheaf.Date exposing (Date)
import Sheaf.Head as Head exposing (Card(..), Kind(..), Tag)
import Sheaf.Html as Html
import Sheaf.Internal.Date as Date
import Sheaf.Internal.Head as Internal
import Test exposing (Test, describe, test)
import Time


suite : Test
suite =
    describe "Sheaf.Head"
        [ renderingTests
        , pathTests
        , problemTests
        ]


{-| A tag as it is rendered on the page `/posts/a/` of a site at
`https://example.com/blog/`.
-}
render : Tag -> String
render tag =
    Internal.toHtml { origin = "https://example.com", basePath = "/blog/", url = "/posts/a/" } tag
        |> List.map Html.toString
        |> String.concat


renderingTests : Test
renderingTests =
    describe "rendering"
        [ test "a description is a meta tag, escaped" <|
            \_ ->
                render (Head.description "Say \"hi\" & <b>")
                    |> Expect.equal "<meta name=\"description\" content=\"Say &quot;hi&quot; &amp; &lt;b&gt;\">"
        , test "the canonical link is the page's absolute URL, under the base path" <|
            \_ ->
                render Head.canonical
                    |> Expect.equal "<link rel=\"canonical\" href=\"https://example.com/blog/posts/a/\">"
        , test "a website's Open Graph tags leave out what is not given" <|
            \_ ->
                render (Head.openGraph { title = "A", description = Nothing, image = Nothing, kind = Website })
                    |> Expect.equal
                        (String.concat
                            [ "<meta property=\"og:title\" content=\"A\">"
                            , "<meta property=\"og:url\" content=\"https://example.com/blog/posts/a/\">"
                            , "<meta property=\"og:type\" content=\"website\">"
                            ]
                        )
        , test "an article's Open Graph tags include its times in UTC" <|
            \_ ->
                render
                    (Head.openGraph
                        { title = "A"
                        , description = Just "About A"
                        , image = Just "/cover.png"
                        , kind = Article { published = novemberThirtieth, modified = Just decemberFirst }
                        }
                    )
                    |> Expect.equal
                        (String.concat
                            [ "<meta property=\"og:title\" content=\"A\">"
                            , "<meta property=\"og:description\" content=\"About A\">"
                            , "<meta property=\"og:image\" content=\"https://example.com/blog/cover.png\">"
                            , "<meta property=\"og:url\" content=\"https://example.com/blog/posts/a/\">"
                            , "<meta property=\"og:type\" content=\"article\">"
                            , "<meta property=\"article:published_time\" content=\"2026-11-29T23:00:00Z\">"
                            , "<meta property=\"article:modified_time\" content=\"2026-12-01T00:00:00Z\">"
                            ]
                        )
        , test "a Twitter card names its kind" <|
            \_ ->
                ( render (Head.twitterCard Summary), render (Head.twitterCard SummaryLargeImage) )
                    |> Expect.equal
                        ( "<meta name=\"twitter:card\" content=\"summary\">"
                        , "<meta name=\"twitter:card\" content=\"summary_large_image\">"
                        )
        , test "feeds are alternate links with their type and title" <|
            \_ ->
                ( render (Head.rssFeed { title = "Posts", path = "/rss.xml" })
                , render (Head.atomFeed { title = "Posts", path = "/atom.xml" })
                )
                    |> Expect.equal
                        ( "<link rel=\"alternate\" type=\"application/rss+xml\" title=\"Posts\" href=\"/blog/rss.xml\">"
                        , "<link rel=\"alternate\" type=\"application/atom+xml\" title=\"Posts\" href=\"/blog/atom.xml\">"
                        )
        , test "any other meta tag has a name and content" <|
            \_ ->
                render (Head.meta { name = "author", content = "Ada" })
                    |> Expect.equal "<meta name=\"author\" content=\"Ada\">"
        ]


pathTests : Test
pathTests =
    describe "paths"
        [ test "a site path gets the base path" <|
            \_ ->
                render (Head.stylesheet "/style.css")
                    |> Expect.equal "<link rel=\"stylesheet\" href=\"/blog/style.css\">"
        , test "an http or https URL is used as given" <|
            \_ ->
                ( render (Head.stylesheet "https://cdn.example.com/x.css")
                , render (Head.openGraph { title = "A", description = Nothing, image = Just "http://example.org/a.png", kind = Website })
                )
                    |> Expect.equal
                        ( "<link rel=\"stylesheet\" href=\"https://cdn.example.com/x.css\">"
                        , String.concat
                            [ "<meta property=\"og:title\" content=\"A\">"
                            , "<meta property=\"og:image\" content=\"http://example.org/a.png\">"
                            , "<meta property=\"og:url\" content=\"https://example.com/blog/posts/a/\">"
                            , "<meta property=\"og:type\" content=\"website\">"
                            ]
                        )
        ]


problemTests : Test
problemTests =
    describe "problems"
        [ test "reports nothing for site paths and full URLs" <|
            \_ ->
                [ Head.stylesheet "/style.css"
                , Head.rssFeed { title = "Posts", path = "https://example.org/rss.xml" }
                , Head.openGraph { title = "A", description = Nothing, image = Just "/cover.png", kind = Website }
                ]
                    |> List.concatMap Internal.problems
                    |> Expect.equal []
        , test "reports a relative path, a path to another host and any other URL" <|
            \_ ->
                [ Head.stylesheet "style.css"
                , Head.atomFeed { title = "Posts", path = "//cdn.example.com/atom.xml" }
                , Head.openGraph { title = "A", description = Nothing, image = Just "data:image/png;base64,AAAA", kind = Website }
                ]
                    |> List.concatMap Internal.problems
                    |> Expect.equal
                        [ { function = "Head.stylesheet", path = "style.css" }
                        , { function = "Head.atomFeed", path = "//cdn.example.com/atom.xml" }
                        , { function = "Head.openGraph", path = "data:image/png;base64,AAAA" }
                        ]
        , test "leaves out a tag whose path is not valid" <|
            \_ ->
                render (Head.stylesheet "style.css")
                    |> Expect.equal ""
        ]


novemberThirtieth : Date
novemberThirtieth =
    Date.fromProtocol
        { posix = Time.millisToPosix 1795993200000
        , isoDate = "2026-11-30"
        , year = 2026
        , month = Time.Nov
        , day = 30
        }


decemberFirst : Date
decemberFirst =
    Date.fromProtocol
        { posix = Time.millisToPosix 1796083200000
        , isoDate = "2026-12-01"
        , year = 2026
        , month = Time.Dec
        , day = 1
        }
