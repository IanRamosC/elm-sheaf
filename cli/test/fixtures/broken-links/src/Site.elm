module Site exposing (site)

import Sheaf
import Sheaf.Collection as Collection exposing (Collection)
import Sheaf.Frontmatter as Frontmatter
import Sheaf.Route as Route


type alias PostMeta =
    { title : String }


posts : Collection PostMeta
posts =
    Collection.named "posts"
        (Frontmatter.succeed PostMeta
            |> Frontmatter.required "title" Frontmatter.string
        )


site : Sheaf.Site
site =
    Sheaf.site
        { metadata =
            { title = "Test site"
            , description = "A site for tests."
            , author = { name = "Ada", email = Nothing }
            , language = "en"
            }
        , routes =
            [ Route.eachItem "/posts/:slug/"
                posts
                (\post -> { title = post.meta.title, head = [], body = post.body })
            ]
        , feeds = []
        }
