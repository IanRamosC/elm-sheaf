module Sheaf.Internal.Html exposing
    ( Html, Attribute, HtmlProblem(..)
    , text, node, attribute, booleanAttribute
    , toString, document, problems
    )

{-| The HTML tree behind `Sheaf.Html`, and everything that interprets it.

It is not exposed by the package so templates cannot build or inspect the tree
directly.

@docs Html, Attribute, HtmlProblem
@docs text, node, attribute, booleanAttribute
@docs toString, document, problems

-}


{-| A piece of a page: text or an element.
-}
type Html
    = Text String
    | Element String (List Attribute) (List Html)


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
    List.member (String.toLower tag) [ "br", "hr", "img", "input", "meta", "link" ]



-- RENDERING


{-| Render a tree as HTML.

Parts that [`problems`](#problems) reports are left out.

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
