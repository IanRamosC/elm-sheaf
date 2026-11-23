module Sheaf.Internal.Html exposing
    ( Html, Attribute, HtmlProblem(..)
    , text, node, attribute, booleanAttribute, link
    , links, resolveLinks
    , toString, document, problems
    )

{-| The HTML tree behind `Sheaf.Html`, and everything that interprets it.

It is not exposed by the package so templates cannot build or inspect the tree
directly.

@docs Html, Attribute, HtmlProblem
@docs text, node, attribute, booleanAttribute, link
@docs links, resolveLinks
@docs toString, document, problems

-}

import Sheaf.Ref exposing (Ref)


{-| A piece of a page: text, an element, or a link to a document whose URL is
not known until the whole site is rendered.
-}
type Html
    = Text String
    | Element String (List Attribute) (List Html)
    | Link Ref (List Html)


{-| An attribute of an element.
-}
type Attribute
    = Valued String String
    | Flag String Bool


{-| Something that makes a tree impossible to render faithfully.

Building a tree cannot fail in Elm, so these are found when the tree is
rendered.

-}
type HtmlProblem
    = InvalidTagName String
    | InvalidAttributeName { tag : String, name : String }
    | RawTextElement String


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


{-| A link to a document, resolved to an `<a href>` by
[`resolveLinks`](#resolveLinks).
-}
link : Ref -> List Html -> Html
link =
    Link



-- LINKS


{-| Every document the tree links to, in document order.
-}
links : Html -> List Ref
links html =
    case html of
        Text _ ->
            []

        Element _ _ children ->
            List.concatMap links children

        Link ref children ->
            ref :: List.concatMap links children


{-| Turn each link to a document into an `<a href>`. A link whose document has
no URL is left as it is.
-}
resolveLinks : (Ref -> Maybe String) -> Html -> Html
resolveLinks resolve html =
    case html of
        Text _ ->
            html

        Element tag attributes children ->
            Element tag attributes (List.map (resolveLinks resolve) children)

        Link ref children ->
            case resolve ref of
                Just url ->
                    Element "a" [ Valued "href" url ] (List.map (resolveLinks resolve) children)

                Nothing ->
                    Link ref (List.map (resolveLinks resolve) children)



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
    if isValidAttributeName (attributeName attr) then
        Nothing

    else
        Just (InvalidAttributeName { tag = tag, name = attributeName attr })


attributeName : Attribute -> String
attributeName attr =
    case attr of
        Valued name _ ->
            name

        Flag name _ ->
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

Parts that [`problems`](#problems) reports are left out, and a link that was
not resolved has no `href`.

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


{-| A complete page. The charset comes first so every page is UTF-8 without
each template having to remember it.
-}
document : { lang : String, head : List Html, body : List Html } -> String
document page =
    String.concat
        [ "<!DOCTYPE html><html lang=\""
        , escape page.lang
        , "\"><head><meta charset=\"utf-8\">"
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
