module Sheaf exposing (Site, site, link)

{-| Sheaf is a static site generator whose templates are written in Elm.

A site is a list of routes. Each route turns a single template, or every
document of a collection, into pages:

    module Site exposing (main)

    import Sheaf
    import Sheaf.Collection as Collection exposing (Collection)
    import Sheaf.Route as Route

    main : Sheaf.Site
    main =
        Sheaf.site
            { language = "en"
            , routes =
                [ Route.single "/" Theme.home
                , Route.eachItem "/posts/:slug/" posts Theme.post
                ]
            }

@docs Site, site, link

-}

import Sheaf.Html exposing (Html)
import Sheaf.Internal.Html as Html
import Sheaf.Internal.Site as Internal
import Sheaf.Ref exposing (Ref)
import Sheaf.Route exposing (Route)


{-| A whole site, ready for the host to build.
-}
type alias Site =
    Internal.Site


{-| A site with these routes, whose pages are in `language` (for the `lang`
attribute of `<html>`).
-}
site : { language : String, routes : List Route } -> Site
site =
    Internal.Site


{-| A link to a document, such as `Sheaf.link Content.Posts.helloWorld [ text "Hello" ]`.

Its URL comes from the [`Route.eachItem`](Sheaf-Route#eachItem) route of the
document's collection. A link to a document that has no page in this build,
such as a draft, is reported when the site is built.

-}
link : Ref -> List Html -> Html
link =
    Html.link
