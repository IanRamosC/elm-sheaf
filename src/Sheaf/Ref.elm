module Sheaf.Ref exposing (Ref, fromId, id)

{-| A reference to a document, which links and templates use instead of a URL.

Every document has a generated value, like `Content.Posts.helloWorld`, so a
renamed or deleted document is a compile error rather than a dead link.

@docs Ref, fromId, id

-}


{-| A reference to one document.
-}
type Ref
    = Ref String


{-| The reference for a document id (`"<collection>/<slug>"`).

This exists for the generated code. Templates should use the generated values,
which the compiler checks, rather than writing ids by hand.

-}
fromId : String -> Ref
fromId =
    Ref


{-| The id of the document, `"<collection>/<slug>"`.
-}
id : Ref -> String
id (Ref documentId) =
    documentId
