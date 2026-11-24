module Sheaf.Feed exposing (Feed)

{-| A feed is an RSS and an Atom file listing the newest documents of a site.

@docs Feed

-}

import Sheaf.Internal.Site as Site


{-| A feed to declare with [`Sheaf.site`](Sheaf#site) or
[`Sheaf.withFeeds`](Sheaf#withFeeds). There is no way to make one yet, so
`feeds = []` is the only value a site can have.
-}
type alias Feed =
    Site.Feed
