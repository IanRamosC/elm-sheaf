module Sheaf.Internal.Site exposing (Site(..), Metadata, Feed, Route(..), Collection(..), Page)

{-| The site a user declares, behind `Sheaf`, `Sheaf.Route` and
`Sheaf.Collection`, which only expose ways to build it.

@docs Site, Metadata, Feed, Route, Collection, Page

-}

import Sheaf.Html exposing (Html)
import Sheaf.Internal.Frontmatter exposing (Frontmatter, Problem)
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


{-| The routes of one site use collections with different `meta` types, so an
item route keeps its collection's decoder and its template together in
`templateFor`. It decodes a document's frontmatter, and gives the template
waiting for the document's rendered body, which may never come.
-}
type Route
    = Single { pattern : String, page : Page }
    | EachItem
        { pattern : String
        , collection : String
        , templateFor : Protocol.Document -> Result (List Problem) (List Html -> Page)
        }


{-| What a template returns for one page.
-}
type alias Page =
    { title : String
    , body : List Html
    }
