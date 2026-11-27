module Sheaf.Internal.Head exposing
    ( Tag(..), OpenGraphType(..), TwitterCard(..), FeedFormat(..)
    , Context, toHtml
    , PathProblem, problems, siteFeed, siteStylesheet
    )

{-| The head tags behind [`Sheaf.Head`](Sheaf-Head), and how they are
rendered.

@docs Tag, OpenGraphType, TwitterCard, FeedFormat
@docs Context, toHtml
@docs PathProblem, problems, siteFeed, siteStylesheet

-}

import Dict exposing (Dict)
import Sheaf.Internal.Date as Date exposing (Date)
import Sheaf.Internal.Html as Html exposing (Html)
import Sheaf.Internal.Path as Path


{-| A tag in a page's `<head>`, kept as what the template asked for, because
its URLs are only known once the page is rendered.
-}
type Tag
    = Description String
    | Canonical
    | OpenGraph
        { title : String
        , description : Maybe String
        , image : Maybe String
        , type_ : OpenGraphType
        }
    | TwitterCard TwitterCard
    | Stylesheet String
    | Icon { path : String, mediaType : String }
    | AlternateFeed FeedFormat { title : String, path : String }
    | Meta { name : String, content : String }


{-| The Open Graph `og:type` of a page.
-}
type OpenGraphType
    = Website
    | Article { published : Date, modified : Maybe Date }


{-| The kind of card Twitter shows for a page.
-}
type TwitterCard
    = Summary
    | SummaryLargeImage


{-| The format of a feed a page points to.
-}
type FeedFormat
    = Rss
    | Atom


{-| Where the page is: the site's origin and base path, and the page's URL
without the base path. The 404 page is served in place of any missing page, so
it has no URL of its own. `stylesheets` has the hashed path of each stylesheet
of the site, by its path, both without a leading slash.
-}
type alias Context =
    { origin : String
    , basePath : String
    , stylesheets : Dict String String
    , url : Maybe String
    }


{-| A path given to a head tag that is neither a site path nor an `http://` or
`https://` URL, with the function it was given to.
-}
type alias PathProblem =
    { function : String
    , path : String
    }


{-| The elements a tag renders as on the page in `context`.

A path that [`problems`](#problems) reports is left out, with the element or
property that holds it.

-}
toHtml : Context -> Tag -> List Html
toHtml context tag =
    case tag of
        Description description ->
            [ metaNamed "description" description ]

        Canonical ->
            case pageUrl context of
                Just url ->
                    [ Html.node "link"
                        [ Html.attribute "rel" "canonical"
                        , Html.attribute "href" url
                        ]
                        []
                    ]

                Nothing ->
                    []

        OpenGraph openGraph ->
            List.filterMap identity
                [ Just (property "og:title" openGraph.title)
                , Maybe.map (property "og:description") openGraph.description
                , openGraph.image
                    |> Maybe.andThen (resolve (absoluteUrl context))
                    |> Maybe.map (property "og:image")
                , Maybe.map (property "og:url") (pageUrl context)
                ]
                ++ openGraphType openGraph.type_

        TwitterCard card ->
            [ metaNamed "twitter:card" (twitterCardName card) ]

        Stylesheet path ->
            resolve (Path.join context.basePath << hashedStylesheet context.stylesheets) path
                |> Maybe.map
                    (\href ->
                        Html.node "link"
                            [ Html.attribute "rel" "stylesheet"
                            , Html.attribute "href" href
                            ]
                            []
                    )
                |> maybeToList

        Icon { path, mediaType } ->
            resolve (Path.join context.basePath) path
                |> Maybe.map
                    (\href ->
                        Html.node "link"
                            [ Html.attribute "rel" "icon"
                            , Html.attribute "href" href
                            , Html.attribute "type" mediaType
                            ]
                            []
                    )
                |> maybeToList

        AlternateFeed format feed ->
            resolve (Path.join context.basePath) feed.path
                |> Maybe.map
                    (\href ->
                        Html.node "link"
                            [ Html.attribute "rel" "alternate"
                            , Html.attribute "type" (feedMediaType format)
                            , Html.attribute "title" feed.title
                            , Html.attribute "href" href
                            ]
                            []
                    )
                |> maybeToList

        Meta { name, content } ->
            [ metaNamed name content ]


metaNamed : String -> String -> Html
metaNamed name content =
    Html.node "meta" [ Html.attribute "name" name, Html.attribute "content" content ] []


property : String -> String -> Html
property name content =
    Html.node "meta" [ Html.attribute "property" name, Html.attribute "content" content ] []


openGraphType : OpenGraphType -> List Html
openGraphType type_ =
    case type_ of
        Website ->
            [ property "og:type" "website" ]

        Article { published, modified } ->
            property "og:type" "article"
                :: property "article:published_time" (Date.toUtcTimestamp published)
                :: (modified
                        |> Maybe.map (\date -> [ property "article:modified_time" (Date.toUtcTimestamp date) ])
                        |> Maybe.withDefault []
                   )


twitterCardName : TwitterCard -> String
twitterCardName card =
    case card of
        Summary ->
            "summary"

        SummaryLargeImage ->
            "summary_large_image"


feedMediaType : FeedFormat -> String
feedMediaType format =
    case format of
        Rss ->
            "application/rss+xml"

        Atom ->
            "application/atom+xml"


maybeToList : Maybe a -> List a
maybeToList maybe =
    case maybe of
        Just value ->
            [ value ]

        Nothing ->
            []



-- PATHS


{-| The format and site path of a tag that links to a feed of this site. A full
URL points to a feed elsewhere, which the site cannot check.
-}
siteFeed : Tag -> Maybe ( FeedFormat, String )
siteFeed tag =
    case tag of
        AlternateFeed format { path } ->
            if Path.isSitePath path then
                Just ( format, path )

            else
                Nothing

        _ ->
            Nothing


{-| The path of a tag that links to a stylesheet of this site. A full URL
points to one elsewhere, which the site cannot check.
-}
siteStylesheet : Tag -> Maybe String
siteStylesheet tag =
    case tag of
        Stylesheet path ->
            if Path.isSitePath path then
                Just path

            else
                Nothing

        _ ->
            Nothing


{-| The name a stylesheet is linked by, which carries a hash of its contents.
A stylesheet the site does not have keeps its path; the page is not written,
since the link is reported.
-}
hashedStylesheet : Dict String String -> String -> String
hashedStylesheet stylesheets path =
    Dict.get (Path.dropLeadingSlash path) stylesheets
        |> Maybe.withDefault path


{-| The page's own URL. Search engines and link previews need it absolute.
-}
pageUrl : Context -> Maybe String
pageUrl context =
    Maybe.map (absoluteUrl context) context.url


absoluteUrl : Context -> String -> String
absoluteUrl context path =
    context.origin ++ Path.join context.basePath path


{-| A full URL as given, or a site path made into a URL by `fromSitePath`.
-}
resolve : (String -> String) -> String -> Maybe String
resolve fromSitePath path =
    if isFullUrl path then
        Just path

    else if Path.isSitePath path then
        Just (fromSitePath path)

    else
        Nothing


isFullUrl : String -> Bool
isFullUrl path =
    String.startsWith "http://" path || String.startsWith "https://" path


{-| Every path in a tag that is neither a site path nor a full URL. A relative
path would point somewhere different from every page.
-}
problems : Tag -> List PathProblem
problems tag =
    let
        check : String -> String -> List PathProblem
        check function path =
            case resolve identity path of
                Just _ ->
                    []

                Nothing ->
                    [ { function = function, path = path } ]
    in
    case tag of
        OpenGraph { image } ->
            image
                |> Maybe.map (check "Head.openGraph")
                |> Maybe.withDefault []

        Stylesheet path ->
            check "Head.stylesheet" path

        Icon { path } ->
            check "Head.icon" path

        AlternateFeed Rss { path } ->
            check "Head.rssFeed" path

        AlternateFeed Atom { path } ->
            check "Head.atomFeed" path

        Description _ ->
            []

        Canonical ->
            []

        TwitterCard _ ->
            []

        Meta _ ->
            []
