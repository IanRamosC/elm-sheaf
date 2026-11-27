module Sheaf.Internal.Site exposing
    ( Site(..), Metadata, Feed(..), Description, Route(..), Grouping, NamedGroup, ListedDocument, Neighbours, FrontmatterProblems, Pagination, Collection(..), SortOrder(..), Page
    , groupingBy
    , nameOf, patternOf, collectionOf, itemPattern, datedCollection, perPageOf, routeGrouping, groupedPattern
    )

{-| The site a user declares, behind `Sheaf`, `Sheaf.Route` and
`Sheaf.Collection`, which only expose ways to build it.

@docs Site, Metadata, Feed, Description, Route, Grouping, NamedGroup, ListedDocument, Neighbours, FrontmatterProblems, Pagination, Collection, SortOrder, Page


# Grouping a collection

@docs groupingBy


# What a route uses

@docs nameOf, patternOf, collectionOf, itemPattern, datedCollection, perPageOf, routeGrouping, groupedPattern

-}

import Sheaf.Html exposing (Html)
import Sheaf.Internal.Component exposing (Component)
import Sheaf.Internal.Frontmatter as Frontmatter exposing (Frontmatter, Problem)
import Sheaf.Internal.Head as Head
import Sheaf.Internal.Pattern as Pattern
import Sheaf.Internal.Protocol as Protocol


{-| What the site says about itself, and every route, feed and component of
it.
-}
type Site
    = Site
        { metadata : Metadata
        , routes : List Route
        , feeds : List Feed
        , components : List Component
        }


{-| The site's title, description, author and the language of its pages.
-}
type alias Metadata =
    Protocol.Metadata


{-| A feed of the site: the paths of its RSS and Atom files, as written, the
collection it lists and how many of its newest documents, if not all. It
decodes a document's frontmatter for its title and summary, as an item route
does for its template. A feed with a grouping is a feed for each group, with
`:group` in its paths.
-}
type Feed
    = Feed
        { rss : String
        , atom : String
        , limit : Maybe Int
        , collection : String
        , grouping : Maybe Grouping
        , describe : Protocol.Document -> Result (List Problem) Description
        }


{-| What a feed item says about its document, besides its content.
-}
type alias Description =
    { title : String
    , summary : Maybe String
    }


{-| A content folder, how to decode the frontmatter of its documents, and
the number in it that orders them, if not their date.
-}
type Collection meta
    = Collection
        { name : String
        , frontmatter : Frontmatter meta
        , order : Maybe (meta -> Int)
        }


{-| How a route orders its collection's documents: by date, or by a number
from their decoded frontmatter, which is `Nothing` when it does not decode.
-}
type SortOrder
    = ByDate
    | ByKey (Protocol.Document -> Maybe Int)


{-| The routes of one site use collections with different `meta` types, so a
route over a collection keeps its collection's decoder and its template
together, in `templateFor`.

An item route decodes the frontmatter of a document and of its neighbours,
and gives the template waiting for the document's rendered body, which may
never come. One that lists its whole collection gets the collection's
documents in order first, once for all its pages. A listing route gets its
documents with their bodies, already in its collection's order, and decodes
them all. A grouped route also keeps how to find a document's group values,
because the renderer groups the documents before any template runs.

-}
type Route
    = Single { pattern : String, page : Page }
    | NotFound Page
    | EachItem
        { pattern : String
        , collection : String
        , order : SortOrder
        , listsCollection : Bool
        , templateFor : List Protocol.Document -> Neighbours -> Result (List Problem) (List Html -> Page)
        }
    | Paginated
        { pattern : String
        , perPage : Int
        , collection : String
        , order : SortOrder
        , templateFor : Pagination -> List ListedDocument -> Result (List FrontmatterProblems) Page
        }
    | AllItems
        { pattern : String
        , collection : String
        , order : SortOrder
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


{-| The collection a route groups, the values each of its documents is
grouped by, from its decoded frontmatter, and the order of each group.
-}
type alias Grouping =
    { collection : String
    , valuesOf : Protocol.Document -> Result (List Problem) (List String)
    , order : SortOrder
    }


{-| A group's display name and its items, in the order of its collection.
-}
type alias NamedGroup item =
    { name : String
    , items : List item
    }


{-| A published document, the documents before and after it in its
collection's reading order, and its rendered body, as a listing route gets
it.
-}
type alias ListedDocument =
    { document : Protocol.Document
    , previous : Maybe Protocol.Document
    , next : Maybe Protocol.Document
    , body : List Html
    }


{-| A published document and the documents before and after it in its
collection's reading order, as an item route gets it.
-}
type alias Neighbours =
    { document : Protocol.Document
    , previous : Maybe Protocol.Document
    , next : Maybe Protocol.Document
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



-- GROUPING A COLLECTION


{-| How to group a collection by the values `by` finds in each document's
frontmatter, ordering each group in `order`.
-}
groupingBy : (meta -> List String) -> SortOrder -> Collection meta -> Grouping
groupingBy by order (Collection collection) =
    { collection = collection.name
    , valuesOf =
        \document ->
            Frontmatter.decode collection.frontmatter { values = document.frontmatter, positions = document.frontmatterPositions }
                |> Result.map by
    , order = order
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


{-| The collection a route lists by date, if it lists one, as an item route
that sees its whole collection does. Its documents need a date.
-}
datedCollection : Route -> Maybe String
datedCollection route =
    case route of
        Paginated listing ->
            byDate listing.order listing.collection

        AllItems listing ->
            byDate listing.order listing.collection

        GroupedBy grouped ->
            byDate grouped.grouping.order grouped.grouping.collection

        AllGroups groups ->
            byDate groups.grouping.order groups.grouping.collection

        EachItem item ->
            if item.listsCollection then
                byDate item.order item.collection

            else
                Nothing

        Single _ ->
            Nothing

        NotFound _ ->
            Nothing


byDate : SortOrder -> String -> Maybe String
byDate order collection =
    case order of
        ByDate ->
            Just collection

        ByKey _ ->
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
routeGrouping : Route -> Maybe Grouping
routeGrouping route =
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
