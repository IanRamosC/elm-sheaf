module Sheaf.Route exposing
    ( Route, Page
    , single, notFound
    , eachItem
    , paginated, allItems, Listing, Pagination
    )

{-| Routes decide which pages a site has and where they are written.

A pattern ending in `/` is a folder, written as its `index.html`: `/` becomes
`index.html` and `/about/` becomes `about/index.html`. Any other pattern is the
file itself, as in `/humans.txt`. Links get the site's base path in front, but
the files do not, because the host serves them from there.

A placeholder such as `:slug` is a whole segment of the pattern, and each kind
of route fills only its own: `/posts/:slug/` is an item route's pattern, and
`/about/:slug/` is not a single page's.

@docs Route, Page


# Pages of their own

@docs single, notFound


# A page for each document

@docs eachItem


# Lists of documents

Listing routes order their documents newest first, by `date`, and documents of
the same date by slug. So every published document of a collection they list
needs a date, from the `date` frontmatter key or the start of its file name.

@docs paginated, allItems, Listing, Pagination

-}

import Sheaf.Collection exposing (Collection)
import Sheaf.Date exposing (Date)
import Sheaf.Document exposing (Document)
import Sheaf.Html exposing (Html)
import Sheaf.Internal.Date as InternalDate
import Sheaf.Internal.Frontmatter as Frontmatter exposing (Problem)
import Sheaf.Internal.Protocol as Protocol
import Sheaf.Internal.Site as Site exposing (FrontmatterProblems, Item)
import Sheaf.Ref as Ref


{-| One or more pages of the site.
-}
type alias Route =
    Site.Route


{-| What a template returns: the page's title, the tags of its `<head>` (see
[`Sheaf.Head`](Sheaf-Head)) and the content of its `<body>`.

    { title = "About", head = [ Head.canonical ], body = [ p [] [ text "Hi" ] ] }

-}
type alias Page =
    Site.Page


{-| A single page at a fixed pattern.

    Route.single "/about/" aboutPage

-}
single : String -> Page -> Route
single pattern page =
    Site.Single { pattern = pattern, page = page }


{-| The page a server shows for a URL with no page, written as `404.html`.

    Route.notFound notFoundPage

It is served in place of any missing page, so it has no URL of its own:
[`Head.canonical`](Sheaf-Head#canonical) renders nothing on it, and it is left
out of the sitemap.

-}
notFound : Page -> Route
notFound =
    Site.NotFound


{-| A page for every published document of a collection, at a pattern where
`:slug` stands for the document's slug.

    Route.eachItem "/posts/:slug/" posts Theme.Post.view

This is also where links to the collection's documents point. When several
`eachItem` routes use the same collection, links use the first in the site's
list of routes.

-}
eachItem : String -> Collection meta -> (Document meta -> Page) -> Route
eachItem pattern collection template =
    Site.EachItem
        { pattern = pattern
        , collection = name collection
        , templateFor = decode collection >> Result.map (\toDocument body -> template (toDocument body))
        }


{-| The published documents of a collection, newest first, on pages of
`perPage` documents each.

    Route.paginated "/" { perPage = 10 } posts Theme.Home.view

The first page is at the pattern, and page `n` at `page/<n>/` under it, so the
pattern ends with `/`: `/`, `/page/2/`, `/page/3/`. A collection with no
published documents still gets its first page, with no items.

-}
paginated : String -> { perPage : Int } -> Collection meta -> (Listing meta -> Page) -> Route
paginated pattern { perPage } collection template =
    Site.Paginated
        { pattern = pattern
        , perPage = perPage
        , collection = name collection
        , templateFor =
            \pagination items ->
                decodeAll collection items
                    |> Result.map (\documents -> template { items = documents, pagination = pagination })
        }


{-| One page with every published document of a collection, newest first.

    Route.allItems "/archive/" posts Theme.Archive.view

-}
allItems : String -> Collection meta -> (List (Document meta) -> Page) -> Route
allItems pattern collection template =
    Site.AllItems
        { pattern = pattern
        , collection = name collection
        , templateFor = decodeAll collection >> Result.map template
        }


{-| The documents on one page of a [`paginated`](#paginated) route, and where
the page is among the others.
-}
type alias Listing meta =
    { items : List (Document meta)
    , pagination : Pagination
    }


{-| Which page this is, counting from 1, of how many, and the URLs of the pages
before and after it, with the site's base path, ready for an `href`:

    case pagination.next of
        Just url ->
            a [ href url ] [ text "Older posts" ]

        Nothing ->
            text ""

-}
type alias Pagination =
    Site.Pagination



-- DOCUMENTS


name : Collection meta -> String
name (Site.Collection collection) =
    collection.name


{-| Decode a document's frontmatter, then wait for its rendered body.
-}
decode : Collection meta -> Protocol.Document -> Result (List Problem) (List Html -> Document meta)
decode (Site.Collection collection) document =
    Frontmatter.decode collection.frontmatter
        { values = document.frontmatter, positions = document.frontmatterPositions }
        |> Result.map
            (\meta body ->
                let
                    date : Maybe Date
                    date =
                        Maybe.map InternalDate.fromProtocol document.date

                    -- The host sends `updated` only when the author wrote one.
                    updated : Maybe Date
                    updated =
                        case document.updated of
                            Just written ->
                                Just (InternalDate.fromProtocol written)

                            Nothing ->
                                date
                in
                { ref = Ref.fromId document.id
                , slug = document.slug
                , date = date
                , updated = updated
                , meta = meta
                , body = body
                }
            )


{-| Every document of a listing, or the problems of each that does not decode.
-}
decodeAll : Collection meta -> List Item -> Result (List FrontmatterProblems) (List (Document meta))
decodeAll collection items =
    let
        decoded : List (Result FrontmatterProblems (Document meta))
        decoded =
            List.map
                (\item ->
                    decode collection item.document
                        |> Result.map (\toDocument -> toDocument item.body)
                        |> Result.mapError (FrontmatterProblems item.document)
                )
                items
    in
    case List.filterMap problemsOf decoded of
        [] ->
            Ok (List.filterMap Result.toMaybe decoded)

        problems ->
            Err problems


problemsOf : Result e a -> Maybe e
problemsOf result =
    case result of
        Ok _ ->
            Nothing

        Err problems ->
            Just problems
