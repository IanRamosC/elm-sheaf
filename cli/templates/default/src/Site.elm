module Site exposing (site)

{-| The site: who writes it, what each post's frontmatter holds, and which
templates and components turn the Markdown into pages.

The templates are in `Theme/`.

-}

import Sheaf
import Sheaf.Blog as Blog
import Sheaf.Frontmatter as Frontmatter exposing (Frontmatter)
import Theme.Components as Components
import Theme.Pages as Pages


site : Sheaf.Site
site =
    Blog.site
        { site = metadata
        , postFrontmatter = postFrontmatter
        , pageFrontmatter = pageFrontmatter
        , postsPerPage = 10
        , feedSize = Just 20
        , tags = .tags
        , feedItem = \post -> { title = post.title, summary = post.summary }
        , layouts =
            { post = Pages.post metadata
            , page = Pages.page metadata
            , index = Pages.index metadata
            , tag = Pages.tag metadata
            , tags = Pages.tags metadata
            , archive = Pages.archive metadata
            , notFound = Pages.notFound metadata
            }
        , components = [ Components.callout ]
        }


metadata : Sheaf.Metadata
metadata =
    { title = "My blog"
    , description = "Notes, written in Markdown and built with Sheaf."
    , author = { name = "Your Name", email = Nothing }
    , language = "en"
    }



-- FRONTMATTER


type alias PostMeta =
    { title : String
    , summary : Maybe String
    , tags : List String
    }


type alias PageMeta =
    { title : String }


postFrontmatter : Frontmatter PostMeta
postFrontmatter =
    Frontmatter.succeed PostMeta
        |> Frontmatter.required "title" Frontmatter.string
        |> Frontmatter.optional "summary" Frontmatter.string
        |> Frontmatter.withDefault "tags" [] (Frontmatter.list Frontmatter.string)


pageFrontmatter : Frontmatter PageMeta
pageFrontmatter =
    Frontmatter.succeed PageMeta
        |> Frontmatter.required "title" Frontmatter.string
