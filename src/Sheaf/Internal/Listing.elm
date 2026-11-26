module Sheaf.Internal.Listing exposing
    ( Body, listOf, readingOrder, paginate, whole
    , missingDates, frontmatterDiagnostic
    )

{-| What listing routes share: their documents in order, cut into pages, and
the problems that keep a listing from being written.

@docs Body, listOf, readingOrder, paginate, whole
@docs missingDates, frontmatterDiagnostic

-}

import Dict
import Sheaf.Html exposing (Html)
import Sheaf.Internal.Compare as Compare
import Sheaf.Internal.Date as Date
import Sheaf.Internal.Frontmatter as Frontmatter
import Sheaf.Internal.Path as Path
import Sheaf.Internal.Pattern as Pattern
import Sheaf.Internal.Protocol exposing (Diagnostic, Document, Severity(..))
import Sheaf.Internal.Results as Results
import Sheaf.Internal.Site exposing (FrontmatterProblems, ListedDocument, Pagination, SortOrder(..))


{-| A published document and its rendered body, or the problems of its body.
-}
type alias Body =
    ( Document, Result (List Diagnostic) (List Html) )


{-| The published documents of a collection in order, and whether every one
of them can be listed: one whose body has problems, or without a date in a
listing by date, would leave a hole in the listing. Their problems are
reported on their own, and the frontmatter of each is still checked, so a body
with problems is given as empty.
-}
listOf : SortOrder -> String -> List Body -> ( List ListedDocument, Bool )
listOf order collection bodies =
    let
        listed : List Body
        listed =
            sorted order (inCollection collection bodies)

        canBeListed : Document -> Bool
        canBeListed document =
            case order of
                ByDate ->
                    document.date /= Nothing

                ByKey _ ->
                    True
    in
    ( List.map (\( document, body ) -> { document = document, body = Result.withDefault [] body }) listed
    , List.all (\( document, body ) -> canBeListed document && isOk body) listed
    )


{-| The published documents of a collection in the order they are read: by
date, the oldest first, which is the reverse of a listing; otherwise in the
order of a listing. A collection by date with an undated document has no
reading order.
-}
readingOrder : SortOrder -> String -> List Body -> Maybe (List Body)
readingOrder order collection bodies =
    let
        documents : List Body
        documents =
            inCollection collection bodies
    in
    case order of
        ByDate ->
            if List.all (\( document, _ ) -> document.date /= Nothing) documents then
                Just (List.reverse (sorted order documents))

            else
                Nothing

        ByKey _ ->
            Just (sorted order documents)


inCollection : String -> List Body -> List Body
inCollection collection bodies =
    List.filter (\( document, _ ) -> document.collection == collection) bodies


sorted : SortOrder -> List Body -> List Body
sorted order bodies =
    case order of
        ByDate ->
            List.sortWith (\( a, _ ) ( b, _ ) -> newestFirst a b) bodies

        ByKey keyOf ->
            -- Each key decodes the document's frontmatter, so it is found once.
            bodies
                |> List.map (\body -> ( keyOf (Tuple.first body), body ))
                |> List.sortWith (\( keyA, ( a, _ ) ) ( keyB, ( b, _ ) ) -> Compare.both (lowestFirst keyA keyB) (Compare.byCodePoint a.slug b.slug))
                |> List.map Tuple.second


isOk : Result e a -> Bool
isOk result =
    case result of
        Ok _ ->
            True

        Err _ ->
            False


{-| The pages of a paginated listing: the URL of each, where it is among the
others, and its documents. The links to the pages before and after have the
base path.
-}
paginate : { basePath : String, pattern : String, perPage : Int } -> List a -> List { url : String, pagination : Pagination, items : List a }
paginate { basePath, pattern, perPage } items =
    let
        chunks : List (List a)
        chunks =
            chunksOf perPage items

        pages : Int
        pages =
            List.length chunks

        linkTo : Int -> Maybe String
        linkTo n =
            if n >= 1 && n <= pages then
                Just (Path.join basePath (Pattern.pageOf n pattern))

            else
                Nothing
    in
    List.indexedMap
        (\i chunk ->
            let
                n : Int
                n =
                    i + 1
            in
            { url = Pattern.pageOf n pattern
            , pagination = { page = n, pages = pages, previous = linkTo (n - 1), next = linkTo (n + 1) }
            , items = chunk
            }
        )
        chunks


{-| At least one chunk, so that an empty listing still has its first page.
-}
chunksOf : Int -> List a -> List (List a)
chunksOf size items =
    case List.drop size items of
        [] ->
            [ List.take size items ]

        rest ->
            List.take size items :: chunksOf size rest


{-| A listing is written whole or not at all, since a missing document or
page would go unnoticed. The frontmatter problems of its documents are
reported either way.
-}
whole : Bool -> List (Result (List FrontmatterProblems) page) -> List (Result (List Diagnostic) page)
whole complete made =
    case List.concatMap Results.errors made of
        [] ->
            if complete then
                List.map Ok (List.filterMap Result.toMaybe made)

            else
                []

        invalid ->
            [ Err (List.concatMap (\{ document, problems } -> List.map (frontmatterDiagnostic document) problems) invalid) ]


{-| A frontmatter problem, in the document's file. Item routes report theirs
with it too.
-}
frontmatterDiagnostic : Document -> Frontmatter.Problem -> Diagnostic
frontmatterDiagnostic document problem =
    { severity = Error
    , title = problem.title
    , message = problem.message
    , sourcePath = Just document.sourcePath
    , span = problem.span
    , hint = problem.hint
    }



-- DATES


{-| A listing by date and a feed order their documents by date, so each needs
one. A document is reported once, however many routes list its collection.
-}
missingDates : List String -> List Document -> List Diagnostic
missingDates listed published =
    published
        |> List.filter (\document -> document.date == Nothing && List.member document.collection listed)
        |> List.map
            (\document ->
                { severity = Error
                , title = "MISSING DATE"
                , message = "This document has no date, but `" ++ document.collection ++ "` is listed by date or in a feed."
                , sourcePath = Just document.sourcePath
                , span = Maybe.map .value (Dict.get "" document.frontmatterPositions)
                , hint = Just "Add `date: YYYY-MM-DD` to its frontmatter, or start its file name with the date."
                }
            )


{-| Newest first, and documents of the same date by slug, so that a listing
does not change from one build to the next.
-}
newestFirst : Document -> Document -> Order
newestFirst a b =
    case ( a.date, b.date ) of
        ( Just dateA, Just dateB ) ->
            case Date.compareNewestFirst (Date.fromProtocol dateA) (Date.fromProtocol dateB) of
                EQ ->
                    Compare.byCodePoint a.slug b.slug

                order ->
                    order

        -- A listing with an undated document is not written, but it is
        -- still put in order to check every document's frontmatter.
        ( Just _, Nothing ) ->
            LT

        ( Nothing, Just _ ) ->
            GT

        ( Nothing, Nothing ) ->
            Compare.byCodePoint a.slug b.slug


{-| The lowest key first. A document whose frontmatter does not decode has no
key, and is put last: the listing is not written, but it is still put in
order to check every document's frontmatter.
-}
lowestFirst : Maybe Int -> Maybe Int -> Order
lowestFirst a b =
    case ( a, b ) of
        ( Just keyA, Just keyB ) ->
            compare keyA keyB

        ( Just _, Nothing ) ->
            LT

        ( Nothing, Just _ ) ->
            GT

        ( Nothing, Nothing ) ->
            EQ
