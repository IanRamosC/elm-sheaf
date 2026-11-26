module Sheaf.Internal.Redirect exposing (Redirect, fileOf, page)

{-| The pages that send a document's old URLs, its `aliases`, to its page.

@docs Redirect, fileOf, page

-}

import Sheaf.Internal.Html as Html
import Sheaf.Internal.Path as Path


{-| A redirect from the alias `from` to the page at `to`, which has no base
path yet. `sourcePath` is the document's, to name it when the alias clashes.
-}
type alias Redirect =
    { from : String
    , to : String
    , sourcePath : String
    }


{-| Where an alias is written in `dist/`. An alias ending in `.html` is that
file, and any other is a folder, written as its `index.html`, because a server
would send a file without an extension as something other than HTML.

    fileOf "/old.html" == "old.html"

    fileOf "/old" == "old/index.html"

-}
fileOf : String -> String
fileOf alias =
    let
        relative : String
        relative =
            Path.dropLeadingSlash alias
    in
    if String.endsWith ".html" relative then
        relative

    else if relative == "" || String.endsWith "/" relative then
        relative ++ "index.html"

    else
        relative ++ "/index.html"


{-| The redirect page to `to`. A browser follows the refresh at once, a search
engine indexes the target instead, and anyone whose browser ignores the
refresh has a link to follow.
-}
page : { language : String, origin : String, basePath : String, to : String } -> String
page { language, origin, basePath, to } =
    let
        target : String
        target =
            Path.join basePath to
    in
    Html.document
        { lang = language
        , head =
            [ Html.node "title" [] [ Html.text "Redirecting…" ]
            , Html.node "meta" [ Html.attribute "http-equiv" "refresh", Html.attribute "content" ("0; url=" ++ target) ] []
            , Html.node "link" [ Html.attribute "rel" "canonical", Html.attribute "href" (origin ++ target) ] []
            , Html.node "meta" [ Html.attribute "name" "robots", Html.attribute "content" "noindex" ] []
            ]
        , body =
            [ Html.node "p"
                []
                [ Html.text "This page has moved to "
                , Html.node "a" [ Html.attribute "href" target ] [ Html.text target ]
                , Html.text "."
                ]
            ]
        }
