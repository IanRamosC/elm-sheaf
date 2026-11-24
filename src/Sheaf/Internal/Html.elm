module Sheaf.Internal.Html exposing
    ( Html, Attribute, Url(..), GroupLink, HtmlProblem(..)
    , text, node, attribute, booleanAttribute, sitePathAttribute, link, groupLink
    , urls, resolveUrls
    , toString, document, problems
    )

{-| The HTML tree behind `Sheaf.Html`, and everything that interprets it.

It is not exposed by the package so templates cannot build or inspect the tree
directly.

@docs Html, Attribute, Url, GroupLink, HtmlProblem
@docs text, node, attribute, booleanAttribute, sitePathAttribute, link, groupLink
@docs urls, resolveUrls
@docs toString, document, problems

-}

import Sheaf.Internal.Path as Path
import Sheaf.Ref exposing (Ref)


{-| A piece of a page: text, an element, or a link whose URL is not known
until the whole site is rendered.
-}
type Html
    = Text String
    | Element String (List Attribute) (List Html)
    | Link Url (List Html)


{-| An attribute of an element. A `Deferred` value is a URL that is not known
until the whole site is rendered.
-}
type Attribute
    = Valued String String
    | Flag String Bool
    | Deferred String Url


{-| A URL that only the renderer can write, because it depends on the site's
routes or its base path.
-}
type Url
    = DocumentUrl Ref
    | SitePath String
    | GroupUrl GroupLink


{-| The page of the group of `value` made by the `groupedBy` route with
`pattern`.
-}
type alias GroupLink =
    { pattern : String
    , value : String
    }


{-| Something that makes a tree impossible to render faithfully.

Building a tree cannot fail in Elm, so these are found when the tree is
rendered.

-}
type HtmlProblem
    = InvalidTagName String
    | InvalidAttributeName { tag : String, name : String }
    | RawTextElement String
    | InvalidSitePath { tag : String, name : String, path : String }


{-| Plain text, escaped when rendered.
-}
text : String -> Html
text =
    Text


{-| An element with any tag name.
-}
node : String -> List Attribute -> List Html -> Html
node =
    Element


{-| An attribute with any name and a text value.
-}
attribute : String -> String -> Attribute
attribute =
    Valued


{-| An attribute that is present or absent, like `checked`.
-}
booleanAttribute : String -> Bool -> Attribute
booleanAttribute =
    Flag


{-| An attribute whose value is a path from the root of the site, given the
base path by [`resolveUrls`](#resolveUrls).
-}
sitePathAttribute : String -> String -> Attribute
sitePathAttribute name path =
    Deferred name (SitePath path)


{-| A link to a document, resolved to an `<a href>` by
[`resolveUrls`](#resolveUrls).
-}
link : Ref -> List Html -> Html
link ref =
    Link (DocumentUrl ref)


{-| A link to the page of a group, resolved to an `<a href>` by
[`resolveUrls`](#resolveUrls).
-}
groupLink : String -> String -> List Html -> Html
groupLink pattern value =
    Link (GroupUrl { pattern = pattern, value = value })



-- URLS


{-| Every URL the tree leaves to the renderer, in document order.
-}
urls : Html -> List Url
urls html =
    case html of
        Text _ ->
            []

        Element _ attributes children ->
            List.filterMap deferredUrl attributes ++ List.concatMap urls children

        Link url children ->
            url :: List.concatMap urls children


deferredUrl : Attribute -> Maybe Url
deferredUrl attr =
    case attr of
        Deferred _ url ->
            Just url

        _ ->
            Nothing


{-| Write every URL the tree leaves to the renderer, in one pass, so that
links and site paths cannot disagree about how a URL is found. A URL that
`resolve` cannot write is left as it is.
-}
resolveUrls : (Url -> Maybe String) -> Html -> Html
resolveUrls resolve html =
    case html of
        Text _ ->
            html

        Element tag attributes children ->
            Element tag
                (List.map (resolveAttribute resolve) attributes)
                (List.map (resolveUrls resolve) children)

        Link url children ->
            case resolve url of
                Just href ->
                    Element "a" [ Valued "href" href ] (List.map (resolveUrls resolve) children)

                Nothing ->
                    Link url (List.map (resolveUrls resolve) children)


resolveAttribute : (Url -> Maybe String) -> Attribute -> Attribute
resolveAttribute resolve attr =
    case attr of
        Deferred name url ->
            resolve url
                |> Maybe.map (Valued name)
                |> Maybe.withDefault attr

        _ ->
            attr



-- PROBLEMS


{-| Every problem in the tree, in document order.
-}
problems : Html -> List HtmlProblem
problems html =
    case html of
        Text _ ->
            []

        Element tag attributes children ->
            if not (isValidTagName tag) then
                [ InvalidTagName tag ]

            else if isRawTextElement tag then
                [ RawTextElement tag ]

            else
                List.filterMap (attributeProblem tag) attributes
                    ++ (if isVoidElement tag then
                            []

                        else
                            List.concatMap problems children
                       )

        Link _ children ->
            List.concatMap problems children


attributeProblem : String -> Attribute -> Maybe HtmlProblem
attributeProblem tag attr =
    if not (isValidAttributeName (attributeName attr)) then
        Just (InvalidAttributeName { tag = tag, name = attributeName attr })

    else
        case attr of
            Deferred name (SitePath path) ->
                if Path.isSitePath path then
                    Nothing

                else
                    Just (InvalidSitePath { tag = tag, name = name, path = path })

            _ ->
                Nothing


attributeName : Attribute -> String
attributeName attr =
    case attr of
        Valued name _ ->
            name

        Flag name _ ->
            name

        Deferred name _ ->
            name


isValidTagName : String -> Bool
isValidTagName =
    isName Char.isAlpha (\c -> Char.isAlphaNum c || c == '-')


isValidAttributeName : String -> Bool
isValidAttributeName =
    isName
        (\c -> Char.isAlpha c || c == '_' || c == ':')
        (\c -> Char.isAlphaNum c || c == '-' || c == '_' || c == ':' || c == '.')


isName : (Char -> Bool) -> (Char -> Bool) -> String -> Bool
isName isFirst isRest name =
    case String.uncons name of
        Just ( first, rest ) ->
            isFirst first && String.all isRest rest

        Nothing ->
            False


{-| Their content is raw text in HTML, so escaping it would corrupt it.
-}
isRawTextElement : String -> Bool
isRawTextElement tag =
    List.member (String.toLower tag) [ "script", "style" ]


isVoidElement : String -> Bool
isVoidElement tag =
    List.member (String.toLower tag)
        [ "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr" ]



-- RENDERING


{-| Render a tree as HTML.

Parts that [`problems`](#problems) reports are left out, and so is a URL that
was not resolved: a link has no `href`, and a site path has no attribute.

-}
toString : Html -> String
toString html =
    case html of
        Text content ->
            escape content

        Element tag attributes children ->
            if not (isValidTagName tag) || isRawTextElement tag then
                ""

            else if isVoidElement tag then
                "<" ++ tag ++ renderAttributes attributes ++ ">"

            else
                "<" ++ tag ++ renderAttributes attributes ++ ">" ++ renderAll children ++ "</" ++ tag ++ ">"

        Link _ children ->
            "<a>" ++ renderAll children ++ "</a>"


renderAll : List Html -> String
renderAll =
    List.map toString >> String.concat


renderAttributes : List Attribute -> String
renderAttributes =
    List.map renderAttribute >> String.concat


renderAttribute : Attribute -> String
renderAttribute attr =
    if not (isValidAttributeName (attributeName attr)) then
        ""

    else
        case attr of
            Valued name value ->
                " " ++ name ++ "=\"" ++ escape value ++ "\""

            Flag name True ->
                " " ++ name

            Flag _ False ->
                ""

            Deferred _ _ ->
                ""


{-| A complete page. The charset and the viewport come first so every page is
UTF-8 and fits a phone's screen without each template having to remember them.
-}
document : { lang : String, head : List Html, body : List Html } -> String
document page =
    String.concat
        [ "<!DOCTYPE html><html lang=\""
        , escape page.lang
        , "\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
        , renderAll page.head
        , "</head><body>"
        , renderAll page.body
        , "</body></html>"
        ]


escape : String -> String
escape =
    String.concat << List.map escapeChar << String.toList


escapeChar : Char -> String
escapeChar char =
    case char of
        '&' ->
            "&amp;"

        '<' ->
            "&lt;"

        '>' ->
            "&gt;"

        '"' ->
            "&quot;"

        '\'' ->
            "&#39;"

        _ ->
            String.fromChar char
