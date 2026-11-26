module Sheaf.Route exposing
    ( Route, Page
    , single, notFound
    , eachItem, eachItemIn
    , paginated, allItems, Listing, Pagination
    , groupedBy, allGroups, Group
    )

{-| Routes decide which pages a site has and where they are written.

A pattern ending in `/` is a folder, written as its `index.html`: `/` becomes
`index.html` and `/about/` becomes `about/index.html`. Any other pattern is the
file itself, as in `/humans.txt`. Links get the site's base path in front, but
the files do not, because the host serves them from there.

The page a server shows for a URL with no page is made by
[`notFound`](#notFound), not by a `single` route at `/404.html`: it keeps that
page out of the sitemap.

A placeholder such as `:slug` is a whole segment of the pattern, and each kind
of route fills only its own: `/posts/:slug/` is an item route's pattern, and
`/about/:slug/` is not a single page's.

@docs Route, Page


# Pages of their own

@docs single, notFound


# A page for each document

@docs eachItem, eachItemIn


# Lists of documents

Listing routes order their documents newest first, by `date`, and documents of
the same date by slug. So every published document of a collection they list
needs a date, from the `date` frontmatter key or the start of its file name.

A collection given [`Collection.orderedBy`](Sheaf-Collection#orderedBy) is
listed by its number instead, lowest first, and its documents need no date.
Each route follows the order of the collection it is given.

@docs paginated, allItems, Listing, Pagination


# Documents grouped by a value

Grouped routes group the published documents of a collection by values of
their frontmatter, such as their tags. Values group together when they have
the same slug, which Sheaf computes before Elm runs: `Elm`, `elm` and `Élm`
are one group with the slug `elm`, and so are `open source` and
`open-source`. A group is shown with its most common spelling.

So the values must come from frontmatter as written: a value changed in Elm,
such as by `String.toUpper`, has no slug and is reported. So are a value with
no letters or digits, such as `+++`, and different words that share a slug,
such as `C` and `C++`.

Like listing routes, they order documents newest first, so each needs a date,
unless the collection is given
[`Collection.orderedBy`](Sheaf-Collection#orderedBy).

@docs groupedBy, allGroups, Group

-}

import Sheaf.Collection exposing (Collection)
import Sheaf.Date exposing (Date)
import Sheaf.Document exposing (Document, Neighbour)
import Sheaf.Html exposing (Html)
import Sheaf.Internal.Date as InternalDate
import Sheaf.Internal.Frontmatter as Frontmatter exposing (Frontmatter, Problem)
import Sheaf.Internal.Image as Image
import Sheaf.Internal.Markdown as Markdown
import Sheaf.Internal.Protocol as Protocol
import Sheaf.Internal.Results as Results
import Sheaf.Internal.Site as Site exposing (FrontmatterProblems, ListedDocument, Neighbours)
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
item routes use the same collection, links use the first in the site's list of
routes, whether made by `eachItem` or [`eachItemIn`](#eachItemIn). Redirects,
like links, use the first item route of a collection, and `previous` and
`next` follow the order of this route's collection.

-}
eachItem : String -> Collection meta -> (Document meta -> Page) -> Route
eachItem pattern collection template =
    itemRoute { listsCollection = False } pattern collection (\_ -> template)


{-| Like [`eachItem`](#eachItem), but the template also gets every published
document of the collection, newest first or in the collection's order, such
as for a sidebar.

    Route.eachItemIn "/guide/:slug/" guide Theme.Guide.view

Each document comes as a [`Neighbour`](Sheaf-Document#Neighbour), without its
body. Like a listing route, it orders them by date, so each needs a date,
unless the collection is given
[`Collection.orderedBy`](Sheaf-Collection#orderedBy).

-}
eachItemIn : String -> Collection meta -> (List (Neighbour meta) -> Document meta -> Page) -> Route
eachItemIn =
    itemRoute { listsCollection = True }


itemRoute : { listsCollection : Bool } -> String -> Collection meta -> (List (Neighbour meta) -> Document meta -> Page) -> Route
itemRoute { listsCollection } pattern collection template =
    Site.EachItem
        { pattern = pattern
        , collection = name collection
        , order = sortOrder collection
        , listsCollection = listsCollection
        , templateFor =
            \documents ->
                let
                    summaries : List (Neighbour meta)
                    summaries =
                        List.filterMap (summarize collection) documents
                in
                decode collection >> Result.map (\toDocument body -> template summaries (toDocument body))
        }


{-| The published documents of a collection, newest first or in the
collection's order, on pages of `perPage` documents each.

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
        , order = sortOrder collection
        , templateFor =
            \pagination items ->
                decodeAll collection items
                    |> Result.map (\documents -> template { items = documents, pagination = pagination })
        }


{-| One page with every published document of a collection, newest first or
in the collection's order.

    Route.allItems "/archive/" posts Theme.Archive.view

-}
allItems : String -> Collection meta -> (List (Document meta) -> Page) -> Route
allItems pattern collection template =
    Site.AllItems
        { pattern = pattern
        , collection = name collection
        , order = sortOrder collection
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


{-| A page for each group, at a pattern where `:group` stands for the group's
slug. The template gets the group's name and its documents.

    Route.groupedBy "/tags/:group/" { by = .tags, perPage = Just 10 } posts Theme.Tag.view

With `perPage = Nothing`, each group is on one page. With `Just n`, page `k`
of a group is at `page/<k>/` under the group's first page, as in
`/tags/elm/page/2/`. Link to a group's page with
[`Sheaf.groupLink`](Sheaf#groupLink).

-}
groupedBy : String -> { by : meta -> List String, perPage : Maybe Int } -> Collection meta -> (String -> Listing meta -> Page) -> Route
groupedBy pattern { by, perPage } collection template =
    Site.GroupedBy
        { pattern = pattern
        , perPage = perPage
        , grouping = groupingOf by collection
        , templateFor =
            \groupName pagination items ->
                decodeAll collection items
                    |> Result.map (\documents -> template groupName { items = documents, pagination = pagination })
        }


{-| One page with every group, ordered by slug, each with its documents.

    Route.allGroups "/tags/" .tags posts Theme.Tags.view

-}
allGroups : String -> (meta -> List String) -> Collection meta -> (List (Group meta) -> Page) -> Route
allGroups pattern by collection template =
    Site.AllGroups
        { pattern = pattern
        , grouping = groupingOf by collection
        , templateFor =
            \groups ->
                groups
                    |> List.map (\group -> decodeAll collection group.items |> Result.map (Group group.name))
                    |> Results.combine
                    |> Result.map template
        }


{-| A group's name, its most common spelling, and its published documents,
newest first or in the collection's order.
-}
type alias Group meta =
    { name : String
    , items : List (Document meta)
    }


groupingOf : (meta -> List String) -> Collection meta -> Site.Grouping
groupingOf by ((Site.Collection { frontmatter }) as collection) =
    { collection = name collection
    , valuesOf = \document -> Result.map by (decodeMeta frontmatter document)
    , order = sortOrder collection
    }



-- DOCUMENTS


name : Collection meta -> String
name (Site.Collection collection) =
    collection.name


{-| How routes over the collection order its documents. A document whose
frontmatter does not decode has no number, and its problems are reported
where the frontmatter is decoded for its template.
-}
sortOrder : Collection meta -> Site.SortOrder
sortOrder (Site.Collection collection) =
    case collection.order of
        Just keyOf ->
            Site.ByKey (\document -> Result.toMaybe (Result.map keyOf (decodeMeta collection.frontmatter document)))

        Nothing ->
            Site.ByDate


decodeMeta : Frontmatter meta -> Protocol.Document -> Result (List Problem) meta
decodeMeta frontmatter document =
    Frontmatter.decode frontmatter { values = document.frontmatter, positions = document.frontmatterPositions }


{-| Decode a document's frontmatter and its neighbours', then wait for its
rendered body.
-}
decode : Collection meta -> Neighbours -> Result (List Problem) (List Html -> Document meta)
decode ((Site.Collection { frontmatter }) as collection) { document, previous, next } =
    decodeMeta frontmatter document
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
                , image = Maybe.map Image.fromProtocol document.image
                , headings = Markdown.headings document.tree
                , previous = Maybe.andThen (summarize collection) previous
                , next = Maybe.andThen (summarize collection) next
                , body = body
                }
            )


{-| A document as a neighbour or in a whole collection, without its body. A
document that does not decode is left out: its problems are reported where its
own page or listing decodes it.
-}
summarize : Collection meta -> Protocol.Document -> Maybe (Neighbour meta)
summarize (Site.Collection collection) document =
    decodeMeta collection.frontmatter document
        |> Result.toMaybe
        |> Maybe.map
            (\meta ->
                { ref = Ref.fromId document.id
                , slug = document.slug
                , date = Maybe.map InternalDate.fromProtocol document.date
                , meta = meta
                }
            )


{-| Every document of a listing, or the problems of each that does not decode.
-}
decodeAll : Collection meta -> List ListedDocument -> Result (List FrontmatterProblems) (List (Document meta))
decodeAll collection items =
    items
        |> List.map
            (\item ->
                decode collection { document = item.document, previous = item.previous, next = item.next }
                    |> Result.map (\toDocument -> toDocument item.body)
                    |> Result.mapError (\problems -> [ FrontmatterProblems item.document problems ])
            )
        |> Results.combine
