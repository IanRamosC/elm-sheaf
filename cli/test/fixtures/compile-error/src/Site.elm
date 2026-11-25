module Site exposing (site)

import Sheaf


site : Sheaf.Site
site =
    Sheaf.site
        { metadata =
            { title = "Test site"
            , description = "A site for tests."
            , author = { name = "Ada", email = Nothing }
            , language = 1
            }
        , routes = []
        , feeds = []
        , components = []
        }
