module Sheaf.Internal.Site exposing (Site(..), Route(..), Collection(..), Page)

{-| The site a user declares, behind `Sheaf`, `Sheaf.Route` and
`Sheaf.Collection`, which only expose ways to build it.

@docs Site, Route, Collection, Page

-}

import Sheaf.Html exposing (Html)
import Sheaf.Internal.Frontmatter exposing (Frontmatter, Problem)
import Sheaf.Internal.Protocol as Protocol


{-| Every route of the site, and the language of its pages.
-}
type Site
    = Site
        { language : String
        , routes : List Route
        }


{-| A content folder and how to decode the frontmatter of its documents.
-}
type Collection meta
    = Collection
        { name : String
        , frontmatter : Frontmatter meta
        }


{-| The routes of one site use collections with different `meta` types, so an
item route keeps its collection's decoder and its template together in
`pageFor`, which only needs a document from the host and its rendered body.
-}
type Route
    = Single { pattern : String, page : Page }
    | EachItem
        { pattern : String
        , collection : String
        , pageFor : Protocol.Document -> List Html -> Result (List Problem) Page
        }


{-| What a template returns for one page.
-}
type alias Page =
    { title : String
    , body : List Html
    }
