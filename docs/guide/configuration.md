# Configuration

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
  "highlight": { "theme": { "light": "github-light", "dark": "github-dark" } },
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

`highlight.theme.light` and `highlight.theme.dark` name the two
[Shiki themes](https://shiki.style/themes) code blocks are highlighted with.
Either can be left out. A name Shiki doesn't have is `BAD CONFIG`, with the
closest theme as a suggestion.

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

## `images`

`images.widths` is the list of widths, in pixels, that local images are resized
to: a non-empty list of whole numbers above 0. `images.formats` lists the
formats written besides each image's own. WebP is the only one Sheaf writes, so
it is `["webp"]`, or `[]` to write each image in its own format only. `"avif"`
is refused, because Bun's image encoder can't write AVIF on Linux, where most
sites are built. See
[Static files and images](static-files-and-images.md).
