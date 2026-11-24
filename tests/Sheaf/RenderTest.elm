module Sheaf.RenderTest exposing (suite)

import Expect
import Json.Encode as Encode exposing (Value)
import Sheaf
import Sheaf.Collection as Collection exposing (Collection)
import Sheaf.Date as Date
import Sheaf.Document exposing (Document)
import Sheaf.Frontmatter as Frontmatter exposing (Frontmatter)
import Sheaf.Head as Head
import Sheaf.Html as Html
import Sheaf.Html.Attributes as Attributes
import Sheaf.Internal.Protocol exposing (Diagnostic, Response, Severity(..), Span)
import Sheaf.Internal.Render as Render
import Sheaf.Ref as Ref
import Sheaf.Route as Route exposing (Page, Route)
import Test exposing (Test, describe, test)
import Time


suite : Test
suite =
    describe "Sheaf.Internal.Render"
        [ pageTests
        , headTests
        , linkTests
        , frontmatterTests
        , collectionTests
        , linkProblemTests
        , invalidHtmlTests
        , duplicateTests
        , badRouteTests
        , badRequestTests
        , siteTests
        ]



-- THE SITE


type alias PostMeta =
    { title : String
    , tags : List String
    }


postMeta : Frontmatter PostMeta
postMeta =
    Frontmatter.succeed PostMeta
        |> Frontmatter.required "title" Frontmatter.string
        |> Frontmatter.withDefault "tags" [] (Frontmatter.list Frontmatter.string)


posts : Collection PostMeta
posts =
    Collection.named "posts" postMeta


postPage : Document PostMeta -> Page
postPage document =
    { title = document.meta.title
    , head = []
    , body = [ Html.article [] (Html.h1 [] [ Html.text document.meta.title ] :: document.body) ]
    }


postRoute : Route
postRoute =
    Route.eachItem "/posts/:slug/" posts postPage


page : List Html.Html -> Page
page body =
    { title = "Home", head = [], body = body }


render : List Route -> Value -> Response
render routes =
    Render.render (Sheaf.site { metadata = metadata, routes = routes, feeds = [] })


metadata : Sheaf.Metadata
metadata =
    { title = "Example"
    , description = "A site."
    , author = { name = "Ada", email = Just "ada@example.com" }
    , language = "en"
    }



-- THE REQUEST


type alias Source =
    { collection : String
    , slug : String
    , date : Maybe String
    , excluded : Bool
    , frontmatter : List ( String, Value )
    , positions : List ( String, Span )
    , body : List Value
    }


post : String -> Source
post slug =
    { collection = "posts"
    , slug = slug
    , date = Nothing
    , excluded = False
    , frontmatter = [ ( "title", Encode.string slug ) ]
    , positions = []
    , body = [ paragraph [ textNode "Hi" ] ]
    }


draft : String -> Source
draft slug =
    let
        published : Source
        published =
            post slug
    in
    { published | excluded = True }


request : List String -> List Source -> Value
request collections sources =
    Encode.object
        [ ( "protocolVersion", Encode.int 2 )
        , ( "build"
          , Encode.object
                [ ( "siteUrl", Encode.string "https://example.com/blog/" )
                , ( "origin", Encode.string "https://example.com" )
                , ( "basePath", Encode.string "/blog/" )
                , ( "mode", Encode.string "production" )
                ]
          )
        , ( "slugs", Encode.list identity [] )
        , ( "collections", Encode.list Encode.string collections )
        , ( "documents", Encode.list encodeSource sources )
        ]


encodeSource : Source -> Value
encodeSource source =
    Encode.object
        [ ( "id", Encode.string (source.collection ++ "/" ++ source.slug) )
        , ( "collection", Encode.string source.collection )
        , ( "sourcePath", Encode.string (sourcePathOf source) )
        , ( "slug", Encode.string source.slug )
        , ( "date"
          , source.date
                |> Maybe.map (\isoDate -> Encode.object [ ( "posixMillis", Encode.int 1795392000000 ), ( "isoDate", Encode.string isoDate ) ])
                |> Maybe.withDefault Encode.null
          )
        , ( "updated", Encode.null )
        , ( "draft", Encode.bool source.excluded )
        , ( "excluded", Encode.bool source.excluded )
        , ( "frontmatter", Encode.object source.frontmatter )
        , ( "frontmatterPositions", Encode.object (List.map (\( path, at ) -> ( path, Encode.object [ ( "value", encodeSpan at ) ] )) source.positions) )
        , ( "tree", markdownNode "root" [ ( "children", Encode.list identity source.body ) ] )
        ]


sourcePathOf : Source -> String
sourcePathOf source =
    "content/" ++ source.collection ++ "/" ++ source.slug ++ ".md"


span : Int -> Int -> Int -> Span
span line from to =
    { start = { line = line, column = from }, end = { line = line, column = to } }


encodeSpan : Span -> Value
encodeSpan at =
    let
        position : { line : Int, column : Int } -> Value
        position { line, column } =
            Encode.object [ ( "line", Encode.int line ), ( "column", Encode.int column ) ]
    in
    Encode.object [ ( "start", position at.start ), ( "end", position at.end ) ]


markdownNode : String -> List ( String, Value ) -> Value
markdownNode type_ fields =
    Encode.object (( "type", Encode.string type_ ) :: ( "position", encodeSpan (span 1 1 2) ) :: fields)


paragraph : List Value -> Value
paragraph children =
    markdownNode "paragraph" [ ( "children", Encode.list identity children ) ]


textNode : String -> Value
textNode value =
    markdownNode "text" [ ( "value", Encode.string value ) ]


{-| A Markdown link to the document `id`, written at `at`.
-}
markdownLink : String -> Span -> Value
markdownLink id at =
    case String.split "/" id of
        [ collection, slug ] ->
            Encode.object
                [ ( "type", Encode.string "sheafLink" )
                , ( "position", encodeSpan at )
                , ( "collection", Encode.string collection )
                , ( "slug", Encode.string slug )
                , ( "children", Encode.list identity [ textNode "link" ] )
                ]

        _ ->
            Encode.null



-- READING THE RESPONSE


paths : Response -> List String
paths response =
    List.map .path response.pages


titles : Response -> List String
titles response =
    List.map .title response.diagnostics


{-| What is between `<body>` and `</body>` on the page at `path`.
-}
bodyAt : String -> Response -> Maybe String
bodyAt =
    between "<body>" "</body>"


{-| What is between `<head>` and `</head>` on the page at `path`.
-}
headAt : String -> Response -> Maybe String
headAt =
    between "<head>" "</head>"


between : String -> String -> String -> Response -> Maybe String
between start end path response =
    response.pages
        |> List.filter (\written -> written.path == path)
        |> List.head
        |> Maybe.andThen
            (\written ->
                case String.split start written.html of
                    [ _, rest ] ->
                        List.head (String.split end rest)

                    _ ->
                        Nothing
            )


error : String -> String -> Diagnostic
error title message =
    { severity = Error
    , title = title
    , message = message
    , sourcePath = Nothing
    , span = Nothing
    , hint = Nothing
    }



-- PAGES


pageTests : Test
pageTests =
    describe "pages"
        [ test "writes an item page at its pattern, without the base path" <|
            \_ ->
                request [ "posts" ] [ post "hello-world" ]
                    |> render [ postRoute ]
                    |> Expect.equal
                        { site = metadata
                        , pages =
                            [ { path = "posts/hello-world/index.html"
                              , html = "<!DOCTYPE html><html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"><title>hello-world</title></head><body><article><h1>hello-world</h1><p>Hi</p></article></body></html>"
                              }
                            ]
                        , feeds = []
                        , sitemap = []
                        , diagnostics = []
                        }
        , test "gives the template the document's ref, slug and date" <|
            \_ ->
                let
                    dated : Source
                    dated =
                        post "hello-world"
                in
                request [ "posts" ] [ { dated | date = Just "2026-11-23" } ]
                    |> render
                        [ Route.eachItem "/posts/:slug/"
                            posts
                            (\document ->
                                page
                                    [ Html.text
                                        (String.join " "
                                            [ Ref.id document.ref
                                            , document.slug
                                            , Maybe.withDefault "" (Maybe.map Date.toIsoDate document.date)
                                            , Maybe.withDefault "" (Maybe.map (Date.toPosix >> Time.posixToMillis >> String.fromInt) document.date)
                                            ]
                                        )
                                    ]
                            )
                        ]
                    |> bodyAt "posts/hello-world/index.html"
                    |> Expect.equal (Just "posts/hello-world hello-world 2026-11-23 1795392000000")
        , test "gives the template the date as the updated date when there is no updated key" <|
            \_ ->
                let
                    dated : Source
                    dated =
                        post "hello-world"
                in
                request [ "posts" ] [ { dated | date = Just "2026-11-23" } ]
                    |> render
                        [ Route.eachItem "/posts/:slug/"
                            posts
                            (\document ->
                                page [ Html.text (Maybe.withDefault "" (Maybe.map Date.toIsoDate document.updated)) ]
                            )
                        ]
                    |> bodyAt "posts/hello-world/index.html"
                    |> Expect.equal (Just "2026-11-23")
        , test "does not render excluded documents" <|
            \_ ->
                request [ "posts" ] [ post "hello-world", draft "secret-plans" ]
                    |> render [ postRoute ]
                    |> paths
                    |> Expect.equal [ "posts/hello-world/index.html" ]
        , test "writes a folder pattern as its index.html and any other pattern as the file" <|
            \_ ->
                request [] []
                    |> render
                        [ Route.single "/" (page [])
                        , Route.single "/about/" (page [])
                        , Route.single "/404.html" (page [])
                        ]
                    |> paths
                    |> Expect.equal [ "index.html", "about/index.html", "404.html" ]
        ]



-- HEAD


headTests : Test
headTests =
    describe "head"
        [ test "every page starts its head with the charset, the viewport and the title" <|
            \_ ->
                request [] []
                    |> render [ Route.single "/" { title = "Home", head = [ Head.description "A site." ], body = [] } ]
                    |> headAt "index.html"
                    |> Expect.equal
                        (Just
                            (String.concat
                                [ "<meta charset=\"utf-8\">"
                                , "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
                                , "<title>Home</title>"
                                , "<meta name=\"description\" content=\"A site.\">"
                                ]
                            )
                        )
        , test "the canonical URL and the Open Graph image are absolute, under the base path" <|
            \_ ->
                request [ "posts" ] [ post "a" ]
                    |> render
                        [ Route.eachItem "/posts/:slug/"
                            posts
                            (\document ->
                                { title = document.meta.title
                                , head =
                                    [ Head.canonical
                                    , Head.openGraph { title = document.meta.title, description = Nothing, image = Just "/cover.png", kind = Head.Website }
                                    ]
                                , body = []
                                }
                            )
                        ]
                    |> headAt "posts/a/index.html"
                    |> Maybe.map
                        (\head ->
                            ( String.contains "<link rel=\"canonical\" href=\"https://example.com/blog/posts/a/\">" head
                            , String.contains "<meta property=\"og:image\" content=\"https://example.com/blog/cover.png\">" head
                            )
                        )
                    |> Expect.equal (Just ( True, True ))
        ]



-- LINKS


homeLinkingTo : String -> Route
homeLinkingTo id =
    Route.single "/" (page [ Sheaf.link (Ref.fromId id) [ Html.text "Hello" ] ])


linkTests : Test
linkTests =
    describe "links"
        [ test "a Sheaf.link points at the item page, under the base path" <|
            \_ ->
                request [ "posts" ] [ post "hello-world" ]
                    |> render [ homeLinkingTo "posts/hello-world", postRoute ]
                    |> bodyAt "index.html"
                    |> Expect.equal (Just "<a href=\"/blog/posts/hello-world/\">Hello</a>")
        , test "a Markdown link points at the item page, under the base path" <|
            \_ ->
                let
                    linking : Source
                    linking =
                        post "linking"
                in
                request [ "posts" ] [ post "hello-world", { linking | body = [ paragraph [ markdownLink "posts/hello-world" (span 5 1 10) ] ] } ]
                    |> render [ postRoute ]
                    |> bodyAt "posts/linking/index.html"
                    |> Expect.equal (Just "<article><h1>linking</h1><p><a href=\"/blog/posts/hello-world/\">link</a></p></article>")
        , test "the first item route of a collection gives its URLs" <|
            \_ ->
                request [ "posts" ] [ post "hello-world" ]
                    |> render
                        [ homeLinkingTo "posts/hello-world"
                        , postRoute
                        , Route.eachItem "/archive/:slug/" posts postPage
                        ]
                    |> bodyAt "index.html"
                    |> Expect.equal (Just "<a href=\"/blog/posts/hello-world/\">Hello</a>")
        , test "a site path in an attribute gets the base path" <|
            \_ ->
                request [] []
                    |> render [ Route.single "/" (page [ Html.a [ Attributes.siteHref "/archive/" ] [ Html.img [ Attributes.siteSrc "/cover.png" ] [] ] ]) ]
                    |> bodyAt "index.html"
                    |> Expect.equal (Just "<a href=\"/blog/archive/\"><img src=\"/blog/cover.png\"></a>")
        , test "Sheaf.Html.toString renders a link that is not resolved without an href" <|
            \_ ->
                Sheaf.link (Ref.fromId "posts/hello-world") [ Html.text "Hello" ]
                    |> Html.toString
                    |> Expect.equal "<a>Hello</a>"
        ]



-- FRONTMATTER


frontmatterTests : Test
frontmatterTests =
    let
        badTags : Source
        badTags =
            post "hello-world"

        source : Source
        source =
            { badTags
                | frontmatter = [ ( "title", Encode.string "Hello" ), ( "tags", Encode.list identity [ Encode.string "elm", Encode.int 42 ] ) ]
                , positions = [ ( "tags", span 3 7 16 ), ( "tags.0", span 3 8 11 ), ( "tags.1", span 3 13 15 ) ]
            }
    in
    describe "frontmatter"
        [ test "a problem is located at the value, in the document's file, and its page is not written" <|
            \_ ->
                request [ "posts" ] [ source ]
                    |> render [ postRoute ]
                    |> Expect.equal
                        { site = metadata
                        , pages = []
                        , feeds = []
                        , sitemap = []
                        , diagnostics =
                            [ { severity = Error
                              , title = "BAD FRONTMATTER"
                              , message = "The `tags` field should be a list of strings, but its second item is a number."
                              , sourcePath = Just "content/posts/hello-world.md"
                              , span = Just (span 3 13 15)
                              , hint = Nothing
                              }
                            ]
                        }
        , test "a problem is reported once when two routes use the document" <|
            \_ ->
                request [ "posts" ] [ source ]
                    |> render [ postRoute, Route.eachItem "/archive/:slug/" posts postPage ]
                    |> titles
                    |> Expect.equal [ "BAD FRONTMATTER" ]
        ]



-- COLLECTIONS


collectionTests : Test
collectionTests =
    describe "collections"
        [ test "a misspelt collection is reported from both sides, each suggesting the other" <|
            \_ ->
                request [ "notes" ] []
                    |> render [ Route.eachItem "/notes/:slug/" (Collection.named "notse" postMeta) postPage ]
                    |> .diagnostics
                    |> Expect.equal
                        [ { severity = Error
                          , title = "UNKNOWN COLLECTION"
                          , message = "A route uses `Collection.named \"notse\"`, but there is no `content/notse` folder."
                          , sourcePath = Nothing
                          , span = Nothing
                          , hint = Just "Did you mean `notes`?\n\nGit does not keep empty folders: add an empty `content/notse/.gitkeep` file and commit it."
                          }
                        , { severity = Error
                          , title = "UNKNOWN COLLECTION"
                          , message = "The folder `content/notes` is a collection, but no route uses `Collection.named \"notes\"`."
                          , sourcePath = Nothing
                          , span = Nothing
                          , hint = Just "Did you mean `notse`?"
                          }
                        ]
        , test "lists the other names when none is close" <|
            \_ ->
                request [ "posts", "pages" ] []
                    |> render [ postRoute, Route.eachItem "/recipes/:slug/" (Collection.named "recipes" postMeta) postPage ]
                    |> .diagnostics
                    |> List.map .hint
                    |> Expect.equal
                        [ Just "The folders in `content/` are `posts` and `pages`.\n\nGit does not keep empty folders: add an empty `content/recipes/.gitkeep` file and commit it."
                        , Just "The routes use `posts` and `recipes`."
                        ]
        , test "a declared collection without a folder reminds that Git does not keep empty folders" <|
            \_ ->
                request [] []
                    |> render [ postRoute ]
                    |> .diagnostics
                    |> List.map .hint
                    |> Expect.equal
                        [ Just "Git does not keep empty folders: add an empty `content/posts/.gitkeep` file and commit it." ]
        , test "an empty folder still counts as a collection" <|
            \_ ->
                request [ "posts" ] []
                    |> render [ postRoute ]
                    |> .diagnostics
                    |> Expect.equal []
        ]



-- LINK PROBLEMS


linkProblemTests : Test
linkProblemTests =
    let
        linkingToDraft : Source
        linkingToDraft =
            let
                linking : Source
                linking =
                    post "hello-world"
            in
            { linking | body = [ paragraph [ markdownLink "posts/secret-plans" (span 5 3 30) ] ] }

        draftHint : Maybe String
        draftHint =
            Just "Publish it, or remove the link. Drafts and future-dated documents are only built by `sheaf dev` and `sheaf build --drafts`."
    in
    describe "link problems"
        [ test "a Markdown link to a draft is located at the link" <|
            \_ ->
                request [ "posts" ] [ linkingToDraft, draft "secret-plans" ]
                    |> render [ postRoute ]
                    |> Expect.equal
                        { site = metadata
                        , pages = []
                        , feeds = []
                        , sitemap = []
                        , diagnostics =
                            [ { severity = Error
                              , title = "LINK TO DRAFT"
                              , message = "This document links to `posts/secret-plans`, which is not published in this build because it is a draft or dated in the future."
                              , sourcePath = Just "content/posts/hello-world.md"
                              , span = Just (span 5 3 30)
                              , hint = draftHint
                              }
                            ]
                        }
        , test "a Markdown link problem does not hide a frontmatter problem" <|
            \_ ->
                request [ "posts" ]
                    [ { linkingToDraft
                        | frontmatter = [ ( "title", Encode.string "Hello" ), ( "tags", Encode.list identity [ Encode.string "elm", Encode.int 42 ] ) ]
                        , positions = [ ( "tags.1", span 3 13 15 ) ]
                      }
                    , draft "secret-plans"
                    ]
                    |> render [ postRoute ]
                    |> titles
                    |> Expect.equal [ "LINK TO DRAFT", "BAD FRONTMATTER" ]
        , test "a Markdown link problem is reported once when two routes use the document" <|
            \_ ->
                request [ "posts" ] [ linkingToDraft, draft "secret-plans" ]
                    |> render [ postRoute, Route.eachItem "/archive/:slug/" posts postPage ]
                    |> titles
                    |> Expect.equal [ "LINK TO DRAFT" ]
        , test "a Sheaf.link to a draft names the route and the page" <|
            \_ ->
                request [ "posts" ] [ post "hello-world", draft "secret-plans" ]
                    |> render
                        [ Route.eachItem "/posts/:slug/"
                            posts
                            (\_ -> page [ Sheaf.link (Ref.fromId "posts/secret-plans") [ Html.text "Plans" ] ])
                        ]
                    |> Expect.equal
                        { site = metadata
                        , pages = []
                        , feeds = []
                        , sitemap = []
                        , diagnostics =
                            [ { severity = Error
                              , title = "LINK TO DRAFT"
                              , message = "While rendering `/posts/hello-world/` from the route `/posts/:slug/`, a `Sheaf.link` points to `posts/secret-plans`, which is not published in this build because it is a draft or dated in the future."
                              , sourcePath = Nothing
                              , span = Nothing
                              , hint = draftHint
                              }
                            ]
                        }
        , test "a link to a collection without an item route has no page" <|
            \_ ->
                request [ "notes" ] [ { collection = "notes", slug = "hello", date = Nothing, excluded = False, frontmatter = [], positions = [], body = [] } ]
                    |> render [ homeLinkingTo "notes/hello" ]
                    |> .diagnostics
                    |> List.filter (\diagnostic -> diagnostic.title == "NO PAGE FOR LINK")
                    |> Expect.equal
                        [ { severity = Error
                          , title = "NO PAGE FOR LINK"
                          , message = "While rendering `/` from the route `/`, a `Sheaf.link` points to `notes/hello`, but no route gives the documents of `notes` a page."
                          , sourcePath = Nothing
                          , span = Nothing
                          , hint = Just "Add a `Route.eachItem` route for the `notes` collection."
                          }
                        ]
        , test "a link to a document that does not exist is broken" <|
            \_ ->
                request [ "posts" ] []
                    |> render [ homeLinkingTo "posts/nowhere", postRoute ]
                    |> .diagnostics
                    |> Expect.equal
                        [ error "BROKEN LINK" "While rendering `/` from the route `/`, a `Sheaf.link` points to `posts/nowhere`, but there is no such document." ]
        ]



-- INVALID HTML


invalidHtmlTests : Test
invalidHtmlTests =
    describe "invalid HTML"
        [ test "a style element is reported and its page is not written" <|
            \_ ->
                request [] []
                    |> render [ Route.single "/" (page [ Html.node "style" [] [ Html.text "p { color: red }" ] ]) ]
                    |> Expect.equal
                        { site = metadata
                        , pages = []
                        , feeds = []
                        , sitemap = []
                        , diagnostics =
                            [ { severity = Error
                              , title = "INVALID HTML"
                              , message = "While rendering `/` from the route `/`, the template made a `<style>` element, whose content cannot be escaped."
                              , sourcePath = Nothing
                              , span = Nothing
                              , hint = Just "Put styles and scripts in files under `static/` and link to them instead."
                              }
                            ]
                        }
        , test "names a bad tag or attribute" <|
            \_ ->
                request [] []
                    |> render
                        [ Route.single "/about/"
                            (page
                                [ Html.node "my element" [] []
                                , Html.div [ Attributes.attribute "on click" "go()" ] []
                                ]
                            )
                        ]
                    |> .diagnostics
                    |> Expect.equal
                        [ error "INVALID HTML" "While rendering `/about/` from the route `/about/`, the template made an element named `my element`, which is not a valid tag name."
                        , error "INVALID HTML" "While rendering `/about/` from the route `/about/`, the template gave a `<div>` element an attribute named `on click`, which is not a valid attribute name."
                        ]
        , test "a site path that does not start with a single slash is reported and its page is not written" <|
            \_ ->
                request [] []
                    |> render
                        [ Route.single "/"
                            (page
                                [ Html.a [ Attributes.siteHref "archive/" ] []
                                , Html.img [ Attributes.siteSrc "//cdn.example.com/x" ] []
                                ]
                            )
                        ]
                    |> Expect.all
                        [ paths >> Expect.equal []
                        , .diagnostics
                            >> Expect.equal
                                [ sitePathError "While rendering `/` from the route `/`, the template gave a `<a>` element the site path `archive/` for its `href`, but a site path starts with a single `/`."
                                , sitePathError "While rendering `/` from the route `/`, the template gave a `<img>` element the site path `//cdn.example.com/x` for its `src`, but a site path starts with a single `/`."
                                ]
                        ]
        , test "a path in the head that is neither a site path nor a full URL is reported" <|
            \_ ->
                request [] []
                    |> render [ Route.single "/" { title = "Home", head = [ Head.stylesheet "style.css" ], body = [] } ]
                    |> Expect.all
                        [ paths >> Expect.equal []
                        , .diagnostics
                            >> Expect.equal
                                [ { severity = Error
                                  , title = "INVALID HTML"
                                  , message = "While rendering `/` from the route `/`, the template gave `Head.stylesheet` the path `style.css`, but a path in the head is either a site path, which starts with a single `/`, or a full `http://` or `https://` URL."
                                  , sourcePath = Nothing
                                  , span = Nothing
                                  , hint = Just "Write a site path from the root of the site, such as `/style.css`. The base path is added for you."
                                  }
                                ]
                        ]
        ]


sitePathError : String -> Diagnostic
sitePathError message =
    { severity = Error
    , title = "INVALID HTML"
    , message = message
    , sourcePath = Nothing
    , span = Nothing
    , hint = Just "Write a site path from the root of the site, such as `/archive/`. The base path is added for you. For a URL on another host, use `href` or `src`."
    }



-- DUPLICATE PAGES


duplicateTests : Test
duplicateTests =
    describe "duplicate pages"
        [ test "two routes making the same page are reported, and the first one is written" <|
            \_ ->
                request [ "posts" ] [ post "hello-world" ]
                    |> render [ Route.single "/posts/hello-world/" (page [ Html.text "first" ]), postRoute ]
                    |> Expect.all
                        [ .diagnostics
                            >> Expect.equal
                                [ error "DUPLICATE PAGE" "The routes `/posts/hello-world/` and `/posts/:slug/` both make the page `posts/hello-world/index.html`." ]
                        , bodyAt "posts/hello-world/index.html" >> Expect.equal (Just "first")
                        ]
        , test "an item route without :slug makes its page more than once" <|
            \_ ->
                request [ "posts" ] [ post "hello-world", post "goodbye", post "again" ]
                    |> render [ Route.eachItem "/posts/" posts postPage ]
                    |> .diagnostics
                    |> Expect.equal
                        [ { severity = Error
                          , title = "DUPLICATE PAGE"
                          , message = "The route `/posts/` makes the page `posts/index.html` more than once."
                          , sourcePath = Nothing
                          , span = Nothing
                          , hint = Just "Put `:slug` in the pattern of an item route, so that each document gets its own page."
                          }
                        ]
        , test "two routes with the same pattern are two routes" <|
            \_ ->
                let
                    page_ : Source
                    page_ =
                        post "about"
                in
                request [ "posts", "pages" ] [ post "about", { page_ | collection = "pages" } ]
                    |> render
                        [ Route.eachItem "/:slug/" posts postPage
                        , Route.eachItem "/:slug/" (Collection.named "pages" postMeta) postPage
                        ]
                    |> .diagnostics
                    |> Expect.equal
                        [ error "DUPLICATE PAGE" "The routes `/:slug/` and `/:slug/` both make the page `about/index.html`." ]
        ]



-- BAD ROUTES


badRouteTests : Test
badRouteTests =
    let
        rejects : String -> String -> Test
        rejects pattern problem =
            test ("rejects `" ++ pattern ++ "`, which " ++ problem) <|
                \_ ->
                    request [ "posts" ] [ post "hello-world" ]
                        |> render [ Route.eachItem pattern posts postPage, Route.single "/" (page []) ]
                        |> Expect.all
                            [ titles >> Expect.equal [ "BAD ROUTE" ]
                            , .diagnostics >> List.map (.message >> String.contains ("`" ++ pattern ++ "`")) >> Expect.equal [ True ]
                            , paths >> Expect.equal [ "index.html" ]
                            ]
    in
    describe "bad routes"
        [ rejects "posts/:slug/" "does not start with a slash"
        , rejects "//posts/:slug/" "has an empty segment"
        , rejects "/posts//:slug/" "has an empty segment in the middle"
        , rejects "/posts/./:slug/" "has a `.` segment"
        , rejects "/posts/../:slug/" "has a `..` segment"
        , rejects "/posts/:slug/?page=1" "has a query"
        , rejects "/posts/:slug/#top" "has a fragment"
        , test "says what a pattern looks like" <|
            \_ ->
                request [] []
                    |> render [ Route.single "//" (page []) ]
                    |> .diagnostics
                    |> Expect.equal
                        [ { severity = Error
                          , title = "BAD ROUTE"
                          , message = "The route `//` has an empty segment, so its pages could not be written."
                          , sourcePath = Nothing
                          , span = Nothing
                          , hint = Just "A pattern starts with `/` and separates its segments with single slashes, as in `/posts/:slug/` or `/404.html`."
                          }
                        ]
        , test "accepts the root, folders and files" <|
            \_ ->
                request [ "posts" ] [ post "hello-world" ]
                    |> render [ Route.single "/" (page []), Route.single "/404.html" (page []), postRoute ]
                    |> Expect.all
                        [ .diagnostics >> Expect.equal []
                        , paths >> Expect.equal [ "index.html", "404.html", "posts/hello-world/index.html" ]
                        ]
        ]



-- BAD REQUESTS


badRequestTests : Test
badRequestTests =
    let
        dated : Source
        dated =
            post "hello-world"
    in
    describe "bad requests"
        [ test "a request that does not decode is reported, with no pages" <|
            \_ ->
                Encode.string "nope"
                    |> render [ Route.single "/" (page []) ]
                    |> Expect.all
                        [ titles >> Expect.equal [ "BAD REQUEST" ]
                        , paths >> Expect.equal []
                        ]
        , test "rejects a date that is not on the calendar" <|
            \_ ->
                [ "2026-13-05", "2026-00-05", "2026-02-30", "2025-02-29", "2026-1-5", "soon" ]
                    |> List.map
                        (\isoDate ->
                            request [ "posts" ] [ { dated | date = Just isoDate } ]
                                |> render [ postRoute ]
                                |> titles
                        )
                    |> Expect.equal (List.repeat 6 [ "BAD REQUEST" ])
        , test "accepts the last day of a leap February" <|
            \_ ->
                request [ "posts" ] [ { dated | date = Just "2028-02-29" } ]
                    |> render [ postRoute ]
                    |> titles
                    |> Expect.equal []
        , test "names a protocol version mismatch" <|
            \_ ->
                Encode.object [ ( "protocolVersion", Encode.int 1 ) ]
                    |> render []
                    |> .diagnostics
                    |> List.map (.message >> (\message -> String.contains "protocol version 1" message && String.contains "speaks 2" message))
                    |> Expect.equal [ True ]
        ]



-- THE SITE METADATA


siteTests : Test
siteTests =
    describe "the site"
        [ test "the response carries the declared metadata" <|
            \_ ->
                request [] []
                    |> render []
                    |> .site
                    |> Expect.equal metadata
        , test "the metadata is sent even when the request is bad" <|
            \_ ->
                Encode.string "nope"
                    |> render []
                    |> .site
                    |> Expect.equal metadata
        , test "withRoutes adds routes after the existing ones" <|
            \_ ->
                request [] []
                    |> Render.render
                        (Sheaf.site { metadata = metadata, routes = [ Route.single "/" (page []) ], feeds = [] }
                            |> Sheaf.withRoutes [ Route.single "/about/" (page []) ]
                        )
                    |> paths
                    |> Expect.equal [ "index.html", "about/index.html" ]
        ]
