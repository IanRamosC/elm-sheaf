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
        { language = "en"
        , routes =
            [ Route.eachItem "/posts/:slug/"
                posts
                (\post -> { title = post.meta.title, body = post.body })
            ]
        }
