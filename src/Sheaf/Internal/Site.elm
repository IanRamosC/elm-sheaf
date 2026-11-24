module Sheaf.Internal.Site exposing
    ( Site(..), Metadata, Feed, Route(..), Grouping, NamedGroup, ListedDocument, FrontmatterProblems, Pagination, Collection(..), Page
    , nameOf, patternOf, collectionOf, itemPattern, listedCollection, perPageOf, groupingOf, groupedPattern
    )

{-| The site a user declares, behind `Sheaf`, `Sheaf.Route` and
`Sheaf.Collection`, which only expose ways to build it.

@docs Site, Metadata, Feed, Route, Grouping, NamedGroup, ListedDocument, FrontmatterProblems, Pagination, Collection, Page


# What a route uses

@docs nameOf, patternOf, collectionOf, itemPattern, listedCollection, perPageOf, groupingOf, groupedPattern

-}

import Sheaf.Html exposing (Html)
import Sheaf.Internal.Frontmatter exposing (Frontmatter, Problem)
import Sheaf.Internal.Head as Head
import Sheaf.Internal.Pattern as Pattern
import Sheaf.Internal.Protocol as Protocol


{-| What the site says about itself, and every route and feed of it.
-}
type Site
    = Site
        { metadata : Metadata
        , routes : List Route
        , feeds : List Feed
        }


{-| The site's title, description, author and the language of its pages.
-}
type alias Metadata =
    Protocol.Metadata


{-| A feed of the site. Nobody can make one yet, because
`Never` has no values, so a site has no feeds.
-}
type Feed
    = Feed Never


{-| A content folder and how to decode the frontmatter of its documents.
-}
type Collection meta
    = Collection
        { name : String
        , frontmatter : Frontmatter meta
        }


{-| The routes of one site use collections with different `meta` types, so a
route over a collection keeps its collection's decoder and its template
together, in `templateFor`.

An item route decodes a document's frontmatter and gives the template waiting
for the document's rendered body, which may never come. A listing route gets
its documents with their bodies, already in order, and decodes them all. A
grouped route also keeps how to find a document's group values, because the
renderer groups the documents before any template runs.

-}
type Route
    = Single { pattern : String, page : Page }
    | NotFound Page
    | EachItem
        { pattern : String
        , collection : String
        , templateFor : Protocol.Document -> Result (List Problem) (List Html -> Page)
        }
    | Paginated
        { pattern : String
        , perPage : Int
        , collection : String
        , templateFor : Pagination -> List ListedDocument -> Result (List FrontmatterProblems) Page
        }
    | AllItems
        { pattern : String
        , collection : String
        , templateFor : List ListedDocument -> Result (List FrontmatterProblems) Page
        }
    | GroupedBy
        { pattern : String
        , perPage : Maybe Int
        , grouping : Grouping
        , templateFor : String -> Pagination -> List ListedDocument -> Result (List FrontmatterProblems) Page
        }
    | AllGroups
        { pattern : String
        , grouping : Grouping
        , templateFor : List (NamedGroup ListedDocument) -> Result (List FrontmatterProblems) Page
        }


{-| The collection a route groups, and the values each of its documents is
grouped by, from its decoded frontmatter.
-}
type alias Grouping =
    { collection : String
    , valuesOf : Protocol.Document -> Result (List Problem) (List String)
    }


{-| A group's display name and its items, newest first.
-}
type alias NamedGroup item =
    { name : String
    , items : List item
    }


{-| A published document and its rendered body, as a listing route gets it.
-}
type alias ListedDocument =
    { document : Protocol.Document
    , body : List Html
    }


{-| The problems of a document's frontmatter.
-}
type alias FrontmatterProblems =
    { document : Protocol.Document
    , problems : List Problem
    }


{-| Where a page of a listing is among its pages. `previous` and `next` are
URLs with the base path, ready for an `href`.
-}
type alias Pagination =
    { page : Int
    , pages : Int
    , previous : Maybe String
    , next : Maybe String
    }


{-| What a template returns for one page: its title, the tags of its `<head>`
and the content of its `<body>`.
-}
type alias Page =
    { title : String
    , head : List Head.Tag
    , body : List Html
    }



-- WHAT A ROUTE USES


{-| How a route is named in messages: by its pattern, or by the function that
makes the one route without a pattern.
-}
nameOf : Route -> String
nameOf route =
    case patternOf route of
        Just ( _, pattern ) ->
            pattern

        Nothing ->
            "Route.notFound"


{-| A route's pattern, and the kind of route that checks it.
-}
patternOf : Route -> Maybe ( Pattern.Kind, String )
patternOf route =
    case route of
        Single single ->
            Just ( Pattern.Fixed, single.pattern )

        NotFound _ ->
            Nothing

        EachItem item ->
            Just ( Pattern.Item, item.pattern )

        Paginated listing ->
            Just ( Pattern.Listing, listing.pattern )

        AllItems listing ->
            Just ( Pattern.Fixed, listing.pattern )

        GroupedBy grouped ->
            case grouped.perPage of
                Just _ ->
                    Just ( Pattern.GroupedListing, grouped.pattern )

                Nothing ->
                    Just ( Pattern.Grouped, grouped.pattern )

        AllGroups groups ->
            Just ( Pattern.Fixed, groups.pattern )


{-| The collection a route takes, if it takes one.
-}
collectionOf : Route -> Maybe String
collectionOf route =
    case route of
        Single _ ->
            Nothing

        NotFound _ ->
            Nothing

        EachItem item ->
            Just item.collection

        Paginated listing ->
            Just listing.collection

        AllItems listing ->
            Just listing.collection

        GroupedBy grouped ->
            Just grouped.grouping.collection

        AllGroups groups ->
            Just groups.grouping.collection


{-| The collection of an item route and its pattern, which links to the
collection's documents use.
-}
itemPattern : Route -> Maybe ( String, String )
itemPattern route =
    case route of
        EachItem item ->
            Just ( item.collection, item.pattern )

        Single _ ->
            Nothing

        NotFound _ ->
            Nothing

        Paginated _ ->
            Nothing

        AllItems _ ->
            Nothing

        GroupedBy _ ->
            Nothing

        AllGroups _ ->
            Nothing


{-| The collection a route lists by date, if it lists one.
-}
listedCollection : Route -> Maybe String
listedCollection route =
    case route of
        Paginated listing ->
            Just listing.collection

        AllItems listing ->
            Just listing.collection

        GroupedBy grouped ->
            Just grouped.grouping.collection

        AllGroups groups ->
            Just groups.grouping.collection

        Single _ ->
            Nothing

        NotFound _ ->
            Nothing

        EachItem _ ->
            Nothing


{-| How many documents a route puts on each page, if it puts them on pages.
-}
perPageOf : Route -> Maybe Int
perPageOf route =
    case route of
        Paginated listing ->
            Just listing.perPage

        GroupedBy grouped ->
            grouped.perPage

        Single _ ->
            Nothing

        NotFound _ ->
            Nothing

        EachItem _ ->
            Nothing

        AllItems _ ->
            Nothing

        AllGroups _ ->
            Nothing


{-| How a route groups its collection, if it does.
-}
groupingOf : Route -> Maybe Grouping
groupingOf route =
    case route of
        GroupedBy grouped ->
            Just grouped.grouping

        AllGroups groups ->
            Just groups.grouping

        Single _ ->
            Nothing

        NotFound _ ->
            Nothing

        EachItem _ ->
            Nothing

        Paginated _ ->
            Nothing

        AllItems _ ->
            Nothing


{-| The pattern of a route with a page for each group, which links to groups
use.
-}
groupedPattern : Route -> Maybe String
groupedPattern route =
    case route of
        GroupedBy grouped ->
            Just grouped.pattern

        Single _ ->
            Nothing

        NotFound _ ->
            Nothing

        EachItem _ ->
            Nothing

        Paginated _ ->
            Nothing

        AllItems _ ->
            Nothing

        AllGroups _ ->
            Nothing
