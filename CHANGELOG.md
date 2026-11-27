# Changelog

All notable changes to Sheaf are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the version
numbers are those of the npm package `elm-sheaf`.

## Unreleased

### Added

- `Head.stylesheet` links a copy of the stylesheet whose name carries a hash of
  its contents, so a changed theme is never served from a stale cache. A path
  that isn't a stylesheet in `static/`, including one with a query string such
  as `/style.css?v=2`, is `UNKNOWN STYLESHEET`.
- `sheaf init` creates a site from a starter blog: a home page, a welcome post,
  an about page, a stylesheet with light and dark colour schemes, and a
  workflow that deploys to GitHub Pages.
- The npm package `elm-sheaf` provides the command `sheaf`, also available as
  `elm-sheaf`, so `bunx elm-sheaf init my-blog` works without installing Sheaf
  first.
- Standalone binaries for macOS (Apple Silicon and Intel), Linux (x64 and
  ARM64) and Windows (x64), which need no Bun, only Elm 0.19.3 on the `PATH`.
  Each release carries them with their `SHA256SUMS` and the licences of the
  code compiled into them.
- `sheaf build` renders the site into `dist/` as plain HTML and CSS, with no
  JavaScript.
- `sheaf dev` serves the site with drafts, rebuilds it on every change and
  reloads the open pages. A build error replaces the page until it is fixed.
- `sheaf check` reports every problem the build would find, without writing
  `dist/`.
- Templates are Elm functions. `Site.elm` declares the site's collections, the
  frontmatter each one holds, and the templates that render them.
- Frontmatter is decoded into Elm records. A missing or misspelled field, or a
  value of the wrong type, fails the build with the file and line.
- `Sheaf.Svg` and `Sheaf.Svg.Attributes` draw inline SVG icons in templates,
  with the names of `elm/svg`.
- Links between documents, written `pages:about` in Markdown or
  `Sheaf.link Content.Pages.about` in Elm, are checked when the site is built.
- The blog preset, `Sheaf.Blog`, makes posts, pages, a paginated index, tag
  pages, an archive, RSS and Atom feeds and a sitemap from a handful of
  layouts. Sites that don't fit it declare their own routes.
- Markdown follows CommonMark and GitHub Flavored Markdown. Directives become
  components rendered by Elm views you write.
- Code blocks are highlighted with Shiki when the site is built, in a light and
  a dark theme: `github-light-default` and `github-dark-default` unless
  `sheaf.json` says otherwise; their colours meet WCAG AA contrast. Shiki's
  GPL-3.0 grammars (`ada`, `gnuplot`, `nginx`, `org`, `racket`) and theme
  (`aurora-x`) are left out, because Sheaf's BSD-3-Clause binaries can't carry
  them.
- A site can add grammars and themes of its own, or replace Shiki's, with
  `highlight.grammars` and `highlight.themes` in `sheaf.json`.
- Local images in Markdown are resized to several widths, encoded as WebP as
  well, and written as `<picture>` elements with their dimensions. Missing
  images and paths whose case doesn't match fail the build.
- Files in `static/` are copied into the site as they are.
- Drafts, dates with a configurable time zone, and cover images.
- Every command checks that the site's `elm.json` gets the Elm package
  `ianramosc/elm-sheaf` exactly once, at a 1.x version this CLI supports.
- `Head.icon` links the site's icon, and the starter uses it for
  `static/favicon.svg`.
- Diagnostics name the file and line, suggest the closest match, and list
  every problem of a kind at once.
- `Collection.orderedBy` reads a collection in the order of a number from its
  documents' frontmatter, instead of by date.
- `Document.previous` and `Document.next` link a document to its neighbours in
  its collection, and the starter's posts end with links to the older and
  newer post.
- `Document.headings` lists a document's headings, and each heading links to
  itself with a `#`. The starter's longer posts start with a table of contents.
- `Route.eachItemIn` makes a page for each document, like `Route.eachItem`,
  and gives its template every document of the collection in order, for a
  sidebar.
- `aliases` in frontmatter keeps a document's old URLs working, with a redirect
  page at each one.
- Every build writes a `robots.txt` naming the sitemap, unless the site has its
  own.
- A page, feed or alias whose file or folder name is over 255 bytes, usually from
  a long tag, is `NAME TOO LONG`, naming the route.
