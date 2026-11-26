# Changelog

All notable changes to Sheaf are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the version
numbers are those of the npm package `elm-sheaf`.

## Unreleased

### Added

- `sheaf init` creates a site from a starter blog: a home page, a welcome post,
  an about page, a stylesheet with light and dark colour schemes, and a
  workflow that deploys to GitHub Pages.
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
- Links between documents, written `pages:about` in Markdown or
  `Sheaf.link Content.Pages.about` in Elm, are checked when the site is built.
- The blog preset, `Sheaf.Blog`, makes posts, pages, a paginated index, tag
  pages, an archive, RSS and Atom feeds and a sitemap from a handful of
  layouts. Sites that don't fit it declare their own routes.
- Markdown follows CommonMark and GitHub Flavored Markdown. Directives become
  components rendered by Elm views you write.
- Code blocks are highlighted with Shiki when the site is built, in a light and
  a dark theme. Shiki's GPL-3.0 grammars (`ada`, `gnuplot`, `nginx`, `org`,
  `racket`) and theme (`aurora-x`) are left out, because Sheaf's
  BSD-3-Clause binaries can't carry them.
- A site can add grammars and themes of its own, or replace Shiki's, with
  `highlight.grammars` and `highlight.themes` in `sheaf.json`.
- Local images in Markdown are resized to several widths, encoded as WebP as
  well, and written as `<picture>` elements with their dimensions. Missing
  images and paths whose case doesn't match fail the build.
- Files in `static/` are copied into the site as they are.
- Drafts, dates with a configurable time zone, and cover images.
- Diagnostics name the file and line, suggest the closest match, and list
  every problem of a kind at once.
