---
title: Configuration
order: 4
description: What goes in sheaf.json and in the site's Elm code, and how to set the site URL, syntax highlighting and images.
---

Most of a site is configured in Elm. `sheaf.json`, at the root of the site,
holds only what Sheaf needs before any Elm runs. The starter's is one line:

```json
{ "siteUrl": "https://example.com/" }
```

Every command looks for `sheaf.json` in the folder it runs in, and stops with
`NO SHEAF.JSON` if there isn't one. Any problem in the file, including a key
Sheaf doesn't know, is `BAD CONFIG`, and Sheaf reports them all at once, with a
suggestion for a misspelled key.

This is every key, with the defaults of those you can leave out:

```json
{
  "siteUrl": "https://example.com/blog/",
  "timezone": "UTC",
  "highlight": {
    "theme": { "light": "github-light", "dark": "github-dark" },
    "grammars": {},
    "themes": {}
  },
  "images": { "widths": [480, 960, 1600], "formats": ["webp"] }
}
```

## `siteUrl`

The address the site is published at, which is required. It must be a full
`http` or `https` URL, without a query or a fragment.

Its path is the site's base path: with `https://example.com/blog/`, every page,
feed, sitemap entry and image is written to be served under `/blog/`, and
`sheaf dev` serves the site under `/blog/` too. This is what a GitHub Pages
project site needs, since it lives at `https://<user>.github.io/<repository>/`.

Feeds, the sitemap, canonical URLs and Open Graph tags use the full address.

`sheaf build --site-url <url>` and `sheaf check --site-url <url>` replace
`siteUrl` for one run. The value is checked the same way, and a bad one is a
`BAD CONFIG` error that names the option. The starter's GitHub Pages workflow
uses it, so the site deploys without editing `sheaf.json` (see
[Deploying](deploying.md)).

`sheaf dev` reads the base path when it starts. If you change it while `dev`
runs, it tells you to restart.

## `timezone`

An IANA timezone name, such as `Europe/Lisbon`. A document dated `2026-11-30`
is published from midnight at the start of that day in this timezone. A date
written with a time and an offset doesn't depend on it. See
[Content](content.md#dates-and-drafts).

## `highlight`

`highlight.theme.light` and `highlight.theme.dark` name the two themes code
blocks are highlighted with: [Shiki's](https://shiki.style/themes), or
[your own](#your-own-grammars-and-themes). Either can be left out, and the
defaults are `github-light-default` and `github-dark-default`, chosen because
their colours pass WCAG AA contrast. A name Sheaf
doesn't have is `BAD CONFIG`, with the closest theme as a suggestion. Sheaf
leaves out Shiki's `aurora-x` theme, because it is GPL-3.0.

Pages use the light theme. To follow the reader's system setting, add Shiki's
dark-mode CSS to your stylesheet, as the starter's `static/style.css` does:

```css
@media (prefers-color-scheme: dark) {
  .shiki,
  .shiki span {
    color: var(--shiki-dark) !important;
    background-color: var(--shiki-dark-bg) !important;
    font-style: var(--shiki-dark-font-style) !important;
    font-weight: var(--shiki-dark-font-weight) !important;
    text-decoration: var(--shiki-dark-text-decoration) !important;
  }
}
```

### Your own grammars and themes

`highlight.grammars` and `highlight.themes` add grammars and themes to Shiki's,
from files in your site:

```json
"highlight": {
  "theme": { "light": "github-light", "dark": "my-theme" },
  "grammars": { "nginx": "highlight/nginx.tmLanguage.json" },
  "themes": { "my-theme": "highlight/my-theme.json" }
}
```

Each key is a name: a code block marked `nginx` uses the grammar named
`nginx`, and `highlight.theme` uses a theme's name. Each value is the path of a
JSON file, relative to the site's folder: a TextMate grammar, with `scopeName`
and `patterns`, or a VS Code colour theme, with `tokenColors` or `colors`.
These are the formats VS Code extensions ship and Shiki loads.

A name can be anything, including one of Shiki's names, and your file is used
instead of Shiki's. A grammar replaces Shiki's grammar of that name together
with its other names: a `javascript` grammar is also used for blocks marked
`js`. So a grammar can't take one of those other names, such as `js`, or one of
the plain names, such as `text`. Other grammars embed a grammar through its
`scopeName`, as `html` embeds `javascript`, so a replacement must keep Shiki's
`scopeName` (`source.js`) for that embedded code to be highlighted. This is
also how a site gets back the GPL-3.0 grammars and theme that Sheaf leaves out.

A file that is missing, isn't JSON or isn't a grammar or theme is `BAD CONFIG`,
naming the key and the file. Code is highlighted again when one of the files
changes, and `sheaf dev` rebuilds when you save one.

## `images`

`images.widths` is the list of widths, in pixels, that local images are resized
to: a non-empty list of whole numbers above 0. `images.formats` lists the
formats written besides each image's own. WebP is the only one Sheaf writes, so
it is `["webp"]`, or `[]` to write each image in its own format only. `"avif"`
is refused, because Bun's image encoder can't write AVIF on Linux, where most
sites are built. See
[Static files and images](static-files-and-images.md).
