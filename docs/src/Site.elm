module Site exposing (site)

{-| The documentation site: the landing page, the guide and the not-found
page.
-}

import Docs.Guide as Guide
import Docs.Home as Home
import Docs.NotFound as NotFound
import Sheaf
import Sheaf.Collection as Collection exposing (Collection)
import Sheaf.Frontmatter as Frontmatter
import Sheaf.Route as Route


site : Sheaf.Site
site =
    Sheaf.site
        { metadata =
            { title = "Sheaf"
            , description = "A static site generator whose templates are written in Elm."
            , author = { name = "Ian Ramos", email = Nothing }
            , language = "en"
            }
        , routes =
            [ Route.allItems "/" pages Home.view
            , Route.allItems "/guide/" guide Guide.index
            , Route.eachItem "/guide/:slug/" guide Guide.page
            , Route.notFound NotFound.view
            ]
        , feeds = []
        , components = []
        }



-- COLLECTIONS


type alias PageMeta =
    { title : String, description : String }


type alias GuideMeta =
    { title : String, order : Int, description : String }


pages : Collection PageMeta
pages =
    Collection.named "pages"
        (Frontmatter.succeed PageMeta
            |> Frontmatter.required "title" Frontmatter.string
            |> Frontmatter.required "description" Frontmatter.string
        )
        |> Collection.orderedBy (\_ -> 0)


guide : Collection GuideMeta
guide =
    Collection.named "guide"
        (Frontmatter.succeed GuideMeta
            |> Frontmatter.required "title" Frontmatter.string
            |> Frontmatter.required "order" Frontmatter.int
            |> Frontmatter.required "description" Frontmatter.string
        )
        |> Collection.orderedBy .order
