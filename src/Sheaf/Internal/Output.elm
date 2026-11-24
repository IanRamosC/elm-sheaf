module Sheaf.Internal.Output exposing (Output(..), pathOf, withoutClashes)

{-| The files a build writes into `dist/`, and the ones that would overwrite
each other.

@docs Output, pathOf, withoutClashes

-}

import Dict exposing (Dict)
import Sheaf.Internal.Check as Check exposing (Location, UncheckedPage)
import Sheaf.Internal.Path as Path
import Sheaf.Internal.Protocol exposing (Diagnostic, Severity(..))


{-| A file of the site: a page, a feed's file in a format such as `RSS` at
its path as written, or the sitemap.
-}
type Output
    = PageFile UncheckedPage
    | FeedFile String String
    | Sitemap


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


{-| The pages of the first output at each file, and a diagnostic for every
later one that would overwrite it or need its name as a folder.

Paths are compared lowercased, because macOS's default disk ignores case: two
files that differ only in case are one file there, but not on Linux.

-}
withoutClashes : List Output -> ( List UncheckedPage, List Diagnostic )
withoutClashes outputs =
    let
        step : Output -> ( Taken, List UncheckedPage, List Diagnostic ) -> ( Taken, List UncheckedPage, List Diagnostic )
        step output ( taken, kept, found ) =
            case clash taken output of
                Just diagnostic ->
                    ( taken, kept, diagnostic :: found )

                Nothing ->
                    ( take output taken
                    , case output of
                        PageFile page ->
                            page :: kept

                        _ ->
                            kept
                    , found
                    )

        ( _, written, clashes ) =
            List.foldl step ( { files = Dict.empty, folders = Dict.empty }, [], [] ) outputs
    in
    ( List.reverse written, List.reverse clashes )


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
            Just (sameFile first output)

        ( Nothing, Just inside, _ ) ->
            Just (fileAndFolder output inside)

        ( Nothing, Nothing, Just first ) ->
            Just (fileAndFolder first output)

        ( Nothing, Nothing, Nothing ) ->
            Nothing



-- MESSAGES


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


duplicatePage : String -> Maybe String -> Diagnostic
duplicatePage message hint =
    { severity = Error
    , title = "DUPLICATE PAGE"
    , message = message
    , sourcePath = Nothing
    , span = Nothing
    , hint = hint
    }
