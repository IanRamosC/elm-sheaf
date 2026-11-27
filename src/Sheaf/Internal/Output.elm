module Sheaf.Internal.Output exposing (Output(..), pathOf, withoutClashes)

{-| The files a build writes into `dist/`, and the ones that would overwrite
each other.

@docs Output, pathOf, withoutClashes

-}

import Dict exposing (Dict)
import Sheaf.Internal.Check as Check exposing (Location, UncheckedPage)
import Sheaf.Internal.Path as Path
import Sheaf.Internal.Protocol exposing (Diagnostic, Severity(..))
import Sheaf.Internal.Redirect as Redirect exposing (Redirect)


{-| A file of the site: a page, a feed's file in a format such as `RSS` at
its path as written, the sitemap, or a redirect from a document's alias.
-}
type Output
    = PageFile UncheckedPage
    | FeedFile String String
    | Sitemap
    | RedirectFile Redirect


{-| Where a page is written in `dist/`. A pattern ending in `/` is a folder,
written as its `index.html`.

    pathOf (At "/posts/a/") == "posts/a/index.html"

-}
pathOf : Location -> String
pathOf location =
    let
        relative : String
        relative =
            Path.dropLeadingSlash (Check.urlOf location)
    in
    if relative == "" || String.endsWith "/" relative then
        relative ++ "index.html"

    else
        relative


fileOf : Output -> String
fileOf output =
    case output of
        PageFile page ->
            pathOf page.location

        FeedFile _ path ->
            Path.dropLeadingSlash path

        Sitemap ->
            "sitemap.xml"

        RedirectFile redirect ->
            Redirect.fileOf redirect.from


{-| The pages and redirects of the first output at each file, and a diagnostic
for every later one that would overwrite it or need its name as a folder, and
for every one with a file or folder name over 255 bytes, which is left out. So
that a page always wins over an alias, redirects come after the other outputs.

Paths are compared lowercased, because macOS's default disk ignores case: two
files that differ only in case are one file there, but not on Linux.

-}
withoutClashes : List Output -> { pages : List UncheckedPage, redirects : List Redirect, diagnostics : List Diagnostic }
withoutClashes outputs =
    let
        step : Output -> ( Taken, List Output, List Diagnostic ) -> ( Taken, List Output, List Diagnostic )
        step output ( taken, kept, found ) =
            case firstJust (longName output) (clash taken output) of
                Just diagnostic ->
                    ( taken, kept, diagnostic :: found )

                Nothing ->
                    ( take output taken, output :: kept, found )

        ( _, written, clashes ) =
            List.foldl step ( { files = Dict.empty, folders = Dict.empty }, [], [] ) outputs

        inOrder : List Output
        inOrder =
            List.reverse written
    in
    { pages = List.filterMap pageOf inOrder
    , redirects = List.filterMap redirectOf inOrder
    , diagnostics = List.reverse clashes
    }


firstJust : Maybe a -> Maybe a -> Maybe a
firstJust first second =
    case first of
        Just _ ->
            first

        Nothing ->
            second


pageOf : Output -> Maybe UncheckedPage
pageOf output =
    case output of
        PageFile page ->
            Just page

        _ ->
            Nothing


redirectOf : Output -> Maybe Redirect
redirectOf output =
    case output of
        RedirectFile redirect ->
            Just redirect

        _ ->
            Nothing


{-| The outputs written so far, by their lowercased file and by every
lowercased folder their file is in.
-}
type alias Taken =
    { files : Dict String Output
    , folders : Dict String Output
    }


take : Output -> Taken -> Taken
take output taken =
    let
        file : String
        file =
            String.toLower (fileOf output)

        -- The first output in a folder is the one a later clash names.
        addFolder : String -> Dict String Output -> Dict String Output
        addFolder folder folders =
            if Dict.member folder folders then
                folders

            else
                Dict.insert folder output folders
    in
    { files = Dict.insert file output taken.files
    , folders = List.foldl addFolder taken.folders (foldersOf file)
    }


{-| `a/b/index.html` is in the folders `a` and `a/b`.
-}
foldersOf : String -> List String
foldersOf file =
    let
        segments : List String
        segments =
            String.split "/" file
    in
    List.range 1 (List.length segments - 1)
        |> List.map (\depth -> String.join "/" (List.take depth segments))


clash : Taken -> Output -> Maybe Diagnostic
clash taken output =
    let
        file : String
        file =
            String.toLower (fileOf output)

        inFile : Maybe Output
        inFile =
            foldersOf file
                |> List.filterMap (\folder -> Dict.get folder taken.files)
                |> List.head
    in
    case ( Dict.get file taken.files, Dict.get file taken.folders, inFile ) of
        ( Just first, _, _ ) ->
            Just (sameFile first output |> pointingAt [ output, first ])

        ( Nothing, Just inside, _ ) ->
            Just (fileAndFolder output inside |> pointingAt [ output, inside ])

        ( Nothing, Nothing, Just first ) ->
            Just (fileAndFolder first output |> pointingAt [ output, first ])

        ( Nothing, Nothing, Nothing ) ->
            Nothing



-- LONG NAMES


{-| Most file systems allow names of up to 255 bytes. Linux's count bytes;
macOS's counts UTF-16 units, and a name never has more of those than bytes, so
this limit is the stricter of the two.
-}
maxNameBytes : Int
maxNameBytes =
    255


longName : Output -> Maybe Diagnostic
longName output =
    String.split "/" (fileOf output)
        |> List.filter (\name -> utf8Length name > maxNameBytes)
        |> List.head
        |> Maybe.map (nameTooLong output)


utf8Length : String -> Int
utf8Length string =
    let
        bytes : Char -> Int
        bytes char =
            let
                code : Int
                code =
                    Char.toCode char
            in
            if code < 0x80 then
                1

            else if code < 0x0800 then
                2

            else if code < 0x00010000 then
                3

            else
                4
    in
    String.foldl (bytes >> (+)) 0 string


nameTooLong : Output -> String -> Diagnostic
nameTooLong output name =
    let
        characters : List Char
        characters =
            String.toList name

        shown : String
        shown =
            if List.length characters > 40 then
                String.fromList (List.take 40 characters) ++ "…"

            else
                name

        hint : Maybe String
        hint =
            case output of
                PageFile _ ->
                    Just "A name in the path comes from the route's pattern or from a frontmatter value, such as a tag. Shorten it."

                RedirectFile _ ->
                    Just "Shorten the alias."

                _ ->
                    Nothing
    in
    { severity = Error
    , title = "NAME TOO LONG"
    , message =
        "The "
            ++ nameOf output
            ++ " makes a path with the name `"
            ++ shown
            ++ "`, which is "
            ++ String.fromInt (utf8Length name)
            ++ " bytes long. Most file systems allow "
            ++ String.fromInt maxNameBytes
            ++ " bytes."
    , sourcePath = Nothing
    , span = Nothing
    , hint = hint
    }
        |> pointingAt [ output ]



-- MESSAGES


{-| A clash involving an alias points at the document the alias is written in,
the later output's when both are aliases. Routes, feeds and the sitemap have no
file to point at.
-}
pointingAt : List Output -> Diagnostic -> Diagnostic
pointingAt outputs diagnostic =
    { diagnostic | sourcePath = List.head (List.filterMap (redirectOf >> Maybe.map .sourcePath) outputs) }


sameFile : Output -> Output -> Diagnostic
sameFile first second =
    let
        ( subjects, noun ) =
            case ( first, second ) of
                ( PageFile a, PageFile b ) ->
                    ( "The routes `" ++ a.routeName ++ "` and `" ++ b.routeName ++ "`", "page" )

                _ ->
                    ( "The " ++ nameOf first ++ " and the " ++ nameOf second, "file" )
    in
    if fileOf first == fileOf second then
        duplicatePage (subjects ++ " both make the " ++ noun ++ " `" ++ fileOf first ++ "`.") Nothing

    else
        duplicatePage (subjects ++ " make the " ++ noun ++ "s `" ++ fileOf first ++ "` and `" ++ fileOf second ++ "`.") caseHint


{-| `inside` is written in a folder with the name of `file`.
-}
fileAndFolder : Output -> Output -> Diagnostic
fileAndFolder file inside =
    duplicatePage
        ("The "
            ++ nameOf file
            ++ " makes the file `"
            ++ fileOf file
            ++ "`, but the "
            ++ nameOf inside
            ++ " makes `"
            ++ fileOf inside
            ++ "`, which needs a folder of that name."
        )
        (if String.startsWith (fileOf file ++ "/") (fileOf inside) then
            Nothing

         else
            caseHint
        )


caseHint : Maybe String
caseHint =
    Just "Paths that differ only in case are one file on a disk that ignores case, as macOS's does."


nameOf : Output -> String
nameOf output =
    case output of
        PageFile page ->
            "route `" ++ page.routeName ++ "`"

        FeedFile format path ->
            format ++ " feed `" ++ path ++ "`"

        Sitemap ->
            "sitemap `/sitemap.xml`"

        RedirectFile redirect ->
            "alias `" ++ redirect.from ++ "` of `" ++ redirect.sourcePath ++ "`"


duplicatePage : String -> Maybe String -> Diagnostic
duplicatePage message hint =
    { severity = Error
    , title = "DUPLICATE PAGE"
    , message = message
    , sourcePath = Nothing
    , span = Nothing
    , hint = hint
    }
