module Sheaf.BlogTest exposing (suite)

import Expect
import Json.Encode as Encode
import RenderFixtures exposing (PostMeta, Source, bodyAt, headAt, metadata, page, paths, post, postMeta, requestWithSlugs)
import Sheaf.Blog as Blog
import Sheaf.Document exposing (Document)
import Sheaf.Head as Head
import Sheaf.Html as Html
import Sheaf.Internal.Protocol exposing (Response)
import Sheaf.Internal.Render as Render
import Sheaf.Route exposing (Page)
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Sheaf.Blog"
        [ test "makes the index, posts, pages, tags, archive and 404 pages, in the order of its routes" <|
            \_ ->
                render [ tagged "a" 1 [ "Elm" ], tagged "b" 2 [ "elm", "Tooling" ], tagged "c" 3 [], about ]
                    |> paths
                    |> Expect.equal
                        [ "index.html"
                        , "page/2/index.html"
                        , "posts/a/index.html"
                        , "posts/b/index.html"
                        , "posts/c/index.html"
                        , "about/index.html"
                        , "tags/index.html"
                        , "tags/elm/index.html"
                        , "tags/tooling/index.html"
                        , "archive/index.html"
                        , "404.html"
                        ]
        , test "pages each tag by postsPerPage" <|
            \_ ->
                render [ tagged "a" 1 [ "Elm" ], tagged "b" 2 [ "Elm" ], tagged "c" 3 [ "Elm" ] ]
                    |> paths
                    |> List.filter (String.startsWith "tags/elm/")
                    |> Expect.equal [ "tags/elm/index.html", "tags/elm/page/2/index.html" ]
        , test "a layout's head gains links to both feeds, titled with the site's title" <|
            \_ ->
                render [ tagged "a" 1 [] ]
                    |> headAt "posts/a/index.html"
                    |> Expect.equal
                        (Just
                            (String.concat
                                [ "<meta charset=\"utf-8\">"
                                , "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
                                , "<title>a</title>"
                                , "<meta name=\"description\" content=\"A post.\">"
                                , "<link rel=\"alternate\" type=\"application/rss+xml\" title=\"Example\" href=\"/blog/feed.xml\">"
                                , "<link rel=\"alternate\" type=\"application/atom+xml\" title=\"Example\" href=\"/blog/atom.xml\">"
                                ]
                            )
                        )
        , test "the 404 page links to the feeds too" <|
            \_ ->
                render []
                    |> headAt "404.html"
                    |> Maybe.map (String.contains "/blog/atom.xml")
                    |> Expect.equal (Just True)
        , test "tagLink links to the tag's page under the base path" <|
            \_ ->
                render [ tagged "a" 1 [ "Elm" ] ]
                    |> bodyAt "posts/a/index.html"
                    |> Expect.equal (Just "<a href=\"/blog/tags/elm/\">Elm</a>")
        ]



-- THE SITE


render : List Source -> Response
render sources =
    requestWithSlugs slugTable [ "posts", "pages" ] sources
        |> Render.render (Blog.site config)


config : Blog.Config PostMeta PostMeta
config =
    { site = metadata
    , postFrontmatter = postMeta
    , pageFrontmatter = postMeta
    , postsPerPage = 2
    , tags = .tags
    , feedItem = \meta -> { title = meta.title, summary = Nothing }
    , layouts =
        { post = postLayout
        , page = titled
        , index = \_ -> page []
        , tag = \_ _ -> page []
        , tags = \_ -> page []
        , archive = \_ -> page []
        , notFound = page []
        }
    }


postLayout : Document PostMeta -> Page
postLayout document =
    { title = document.meta.title
    , head = [ Head.description "A post." ]
    , body = List.map (\tag -> Blog.tagLink tag [ Html.text tag ]) document.meta.tags
    }


titled : Document PostMeta -> Page
titled document =
    { title = document.meta.title, head = [], body = [] }


slugTable : List ( String, String, String )
slugTable =
    [ ( "Elm", "elm", "elm" )
    , ( "elm", "elm", "elm" )
    , ( "Tooling", "tooling", "tooling" )
    ]


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


about : Source
about =
    let
        source : Source
        source =
            post "about"
    in
    { source | collection = "pages" }
