module Sheaf.Internal.Check exposing
    ( Location(..), urlOf, UncheckedPage, Build, check, CheckedPage
    , BrokenLink, LinkProblem(..), GroupLinkProblem(..), linkDiagnostic
    , brokenLinkDiagnostics
    )

{-| Checking the pages routes made, before they are written: their HTML, the
paths in their heads and their links to documents.

A broken link is reported once for all the pages of a route that have it,
since a layout they share usually made it.

@docs Location, urlOf, UncheckedPage, Build, check, CheckedPage
@docs BrokenLink, LinkProblem, GroupLinkProblem, linkDiagnostic
@docs brokenLinkDiagnostics

-}

import Sheaf.Html exposing (Html)
import Sheaf.Internal.Head as Head
import Sheaf.Internal.Hint as Hint
import Sheaf.Internal.Html as Html exposing (GroupLink, HtmlProblem(..), Url(..))
import Sheaf.Internal.Protocol as Protocol exposing (Diagnostic, Severity(..))
import Sheaf.Internal.Site exposing (Page)
import Sheaf.Ref as Ref exposing (Ref)



-- PAGES


{-| Where a page is served. The 404 page is served in place of any missing
page, so it has no URL of its own.
-}
type Location
    = At String
    | InPlaceOfMissingPages


{-| The URL a page is written at, and named by in messages.
-}
urlOf : Location -> String
urlOf location =
    case location of
        At url ->
            url

        InPlaceOfMissingPages ->
            "/404.html"


{-| A page a route made, before its links are resolved and it is checked.

`route` is the route's place in the site's list, because two routes can have
the same pattern.

-}
type alias UncheckedPage =
    { route : Int
    , routeName : String
    , location : Location
    , page : Page
    }


{-| A page with the problems found in it. Its broken links are reported
together with the same ones on other pages of its route, since they usually
come from a layout they share.
-}
type alias CheckedPage =
    { unchecked : UncheckedPage
    , head : List Html
    , brokenLinks : List BrokenLink
    , problems : List Diagnostic
    }


{-| What checking a page needs from the build: where the site is, and what is
wrong with a link to a document or a group, if anything.
-}
type alias Build =
    { origin : String
    , basePath : String
    , linkProblem : Ref -> Maybe LinkProblem
    , groupLinkProblem : GroupLink -> Maybe GroupLinkProblem
    }


{-| Find a page's problems, and render its head.
-}
check : Build -> UncheckedPage -> CheckedPage
check build unchecked =
    let
        page : Page
        page =
            unchecked.page

        subject : String
        subject =
            "While rendering `" ++ urlOf unchecked.location ++ "` from the route `" ++ unchecked.routeName ++ "`,"

        ownUrl : Maybe String
        ownUrl =
            case unchecked.location of
                At url ->
                    Just url

                InPlaceOfMissingPages ->
                    Nothing

        head : List Html
        head =
            Html.node "title" [] [ Html.text page.title ]
                :: List.concatMap (Head.toHtml { origin = build.origin, basePath = build.basePath, url = ownUrl }) page.head
    in
    { unchecked = unchecked
    , head = head
    , brokenLinks =
        page.body
            |> List.concatMap Html.urls
            |> List.filterMap
                (\target ->
                    case target of
                        DocumentUrl ref ->
                            Maybe.map (BrokenDocumentLink ref) (build.linkProblem ref)

                        GroupUrl link ->
                            Maybe.map (BrokenGroupLink link) (build.groupLinkProblem link)

                        SitePath _ ->
                            Nothing
                )

    -- Checked before resolving, which would hide a bad site path.
    , problems =
        List.map (invalidHtml subject) (List.concatMap Html.problems (head ++ page.body))
            ++ List.map (invalidHeadPath subject) (List.concatMap Head.problems page.head)
    }



-- LINKS


{-| A link of a template with nowhere to point, and why.
-}
type BrokenLink
    = BrokenDocumentLink Ref LinkProblem
    | BrokenGroupLink GroupLink GroupLinkProblem


{-| Why a link to a group has nowhere to point. `NoGroupedRoute` has the
patterns of the site's `groupedBy` routes, to suggest one.
-}
type GroupLinkProblem
    = NoGroupedRoute (List String)
    | ValueWithoutSlug
    | EmptyGroup


{-| Why a link to a document has nowhere to point.
-}
type LinkProblem
    = ToDraft
    | ToCollectionWithoutPages String
    | ToNothing


{-| A diagnostic for a link, given where it was written: the start of its
message, and the source path and span when it was written in Markdown.
-}
linkDiagnostic : { subject : String, sourcePath : Maybe String, span : Maybe Protocol.Span } -> Ref -> LinkProblem -> Diagnostic
linkDiagnostic origin ref problem =
    let
        target : String
        target =
            origin.subject ++ " `" ++ Ref.id ref ++ "`"

        located : String -> String -> Maybe String -> Diagnostic
        located title message hint =
            { severity = Error
            , title = title
            , message = message
            , sourcePath = origin.sourcePath
            , span = origin.span
            , hint = hint
            }
    in
    case problem of
        ToDraft ->
            located "LINK TO DRAFT"
                (target ++ ", which is not published in this build because it is a draft or dated in the future.")
                (Just "Publish it, or remove the link. Drafts and future-dated documents are only built by `sheaf dev` and `sheaf build --drafts`.")

        ToCollectionWithoutPages collection ->
            located "NO PAGE FOR LINK"
                (target ++ ", but no route gives the documents of `" ++ collection ++ "` a page.")
                (Just ("Add a `Route.eachItem` route for the `" ++ collection ++ "` collection."))

        ToNothing ->
            located "BROKEN LINK" (target ++ ", but there is no such document.") Nothing


{-| The broken links of the pages, one diagnostic for each link problem,
reference and route, in the order they are first found.
-}
brokenLinkDiagnostics : List CheckedPage -> List Diagnostic
brokenLinkDiagnostics pages =
    List.map brokenLinkDiagnostic (groupBrokenLinks pages)


{-| The same broken link on the pages of one route. A page links to it once or
more, and is counted once: its URL is the last one counted.
-}
type alias RepeatedLink =
    { route : Int
    , routeName : String
    , link : BrokenLink
    , firstUrl : String
    , lastUrl : String
    , pages : Int
    }


groupBrokenLinks : List CheckedPage -> List RepeatedLink
groupBrokenLinks pages =
    List.foldl
        (\{ unchecked, brokenLinks } found -> List.foldl (addBrokenLink unchecked) found brokenLinks)
        []
        pages


addBrokenLink : UncheckedPage -> BrokenLink -> List RepeatedLink -> List RepeatedLink
addBrokenLink page link found =
    let
        isSame : RepeatedLink -> Bool
        isSame repeated =
            repeated.route == page.route && repeated.link == link

        url : String
        url =
            urlOf page.location
    in
    if List.any isSame found then
        List.map
            (\repeated ->
                if isSame repeated && repeated.lastUrl /= url then
                    { repeated | lastUrl = url, pages = repeated.pages + 1 }

                else
                    repeated
            )
            found

    else
        found ++ [ { route = page.route, routeName = page.routeName, link = link, firstUrl = url, lastUrl = url, pages = 1 } ]


{-| The diagnostic of a broken link, naming its page, or how many pages of its
route have it.
-}
brokenLinkDiagnostic : RepeatedLink -> Diagnostic
brokenLinkDiagnostic repeated =
    let
        subject : String
        subject =
            if repeated.pages == 1 then
                "While rendering `" ++ repeated.firstUrl ++ "` from the route `" ++ repeated.routeName ++ "`,"

            else
                "While rendering "
                    ++ String.fromInt repeated.pages
                    ++ " pages from the route `"
                    ++ repeated.routeName
                    ++ "` (the first is `"
                    ++ repeated.firstUrl
                    ++ "`),"
    in
    case repeated.link of
        BrokenDocumentLink ref problem ->
            linkDiagnostic
                { subject = subject ++ " a `Sheaf.link` points to"
                , sourcePath = Nothing
                , span = Nothing
                }
                ref
                problem

        BrokenGroupLink link problem ->
            groupLinkDiagnostic (subject ++ " a `Sheaf.groupLink` points to") link problem


groupLinkDiagnostic : String -> GroupLink -> GroupLinkProblem -> Diagnostic
groupLinkDiagnostic subject link problem =
    let
        target : String
        target =
            subject ++ " the group `" ++ link.value ++ "` of `" ++ link.pattern ++ "`"

        diagnostic : String -> String -> Maybe String -> Diagnostic
        diagnostic title message hint =
            { severity = Error
            , title = title
            , message = message
            , sourcePath = Nothing
            , span = Nothing
            , hint = hint
            }
    in
    case problem of
        NoGroupedRoute patterns ->
            diagnostic "NO PAGE FOR LINK"
                (target ++ ", but no `Route.groupedBy` route has that pattern.")
                (Hint.didYouMean (\names -> "The `Route.groupedBy` patterns are " ++ names ++ ".") patterns link.pattern
                    |> Maybe.withDefault "Add a `Route.groupedBy` route with this pattern."
                    |> Just
                )

        ValueWithoutSlug ->
            diagnostic "MISSING SLUG"
                (target ++ ", but `" ++ link.value ++ "` has no slug.")
                (Just "Group values must come from frontmatter as written; Sheaf computes their slugs before Elm runs.")

        EmptyGroup ->
            diagnostic "LINK TO EMPTY GROUP"
                (target ++ ", but no published document is in it.")
                (Just "Publish a document with this value, or remove the link. Drafts and future-dated documents are only built by `sheaf dev` and `sheaf build --drafts`.")



-- HTML


invalidHtml : String -> HtmlProblem -> Diagnostic
invalidHtml subject problem =
    let
        diagnostic : String -> Maybe String -> Diagnostic
        diagnostic message hint =
            { severity = Error
            , title = "INVALID HTML"
            , message = subject ++ " the template " ++ message
            , sourcePath = Nothing
            , span = Nothing
            , hint = hint
            }
    in
    case problem of
        InvalidTagName tag ->
            diagnostic ("made an element named `" ++ tag ++ "`, which is not a valid tag name.") Nothing

        InvalidAttributeName { tag, name } ->
            diagnostic ("gave a `<" ++ tag ++ ">` element an attribute named `" ++ name ++ "`, which is not a valid attribute name.") Nothing

        RawTextElement tag ->
            diagnostic ("made a `<" ++ tag ++ ">` element, whose content cannot be escaped.")
                (Just "Put styles and scripts in files under `static/` and link to them instead.")

        InvalidSitePath { tag, name, path } ->
            diagnostic ("gave a `<" ++ tag ++ ">` element the site path `" ++ path ++ "` for its `" ++ name ++ "`, but a site path starts with a single `/`.")
                (Just "Write a site path from the root of the site, such as `/archive/`. The base path is added for you. For a URL on another host, use `href` or `src`.")


invalidHeadPath : String -> Head.PathProblem -> Diagnostic
invalidHeadPath subject { function, path } =
    { severity = Error
    , title = "INVALID HTML"
    , message =
        subject
            ++ " the template gave `"
            ++ function
            ++ "` the path `"
            ++ path
            ++ "`, but a path in the head is either a site path, which starts with a single `/`, or a full `http://` or `https://` URL."
    , sourcePath = Nothing
    , span = Nothing
    , hint = Just "Write a site path from the root of the site, such as `/style.css`. The base path is added for you."
    }
