# Sheaf

Sheaf is a static site generator whose templates are written in Elm. You describe
your site's pages as typed Elm functions, keep your content in Markdown with
frontmatter, and Sheaf renders the whole site to plain HTML files.

The repository holds two packages:

- the root is the Elm package `ianramosc/elm-sheaf`, the library your templates import;
- `cli/` is the npm package `elm-sheaf`, the Bun and TypeScript host that builds the site.

## Requirements and commands

Sheaf needs [Elm 0.19.3](https://guide.elm-lang.org/install/elm.html) and
[Bun](https://bun.sh). It finds `elm` in your site's `node_modules/.bin` or on
your `PATH`.

Run these in your site's folder:

- `sheaf build` renders the site into `dist/`;
- `sheaf check` runs every build stage, reporting every problem it finds,
  without writing `dist/`.

Both take `--drafts` to include drafts and documents dated in the future.

## What works today

- Markdown collections with typed frontmatter, checked links between documents,
  and drafts and future-dated posts left out of production builds.
- Routes for a single page, a page per document, paginated lists, pages grouped
  by a frontmatter value such as tags, one page of every document or every
  group, and the 404 page. Tags that differ only in case or accents share a
  page, and links to tag pages are checked.
- The `Sheaf.Blog` preset: posts, pages, a paginated index, tag pages, an
  archive and a 404 page from a handful of layouts. It uses only the public
  API, so a site can do the same without it, or add routes and feeds next to it.
- RSS and Atom feeds with each post's full HTML and absolute links, and a
  `sitemap.xml` of every page but the 404 page.
- Head tags for search engines and link previews: description, canonical URL,
  Open Graph, Twitter cards, stylesheets and feed links.
- Sites served under a base path, such as `https://example.com/blog/`.
- Code blocks highlighted at build time by [Shiki](https://shiki.style/), in a
  light and a dark theme (`github-light` and `github-dark` unless `sheaf.json`
  says otherwise). A block marked with a language Shiki doesn't know is an
  error; use `text` for a block without highlighting.

  Pages use the light theme. To switch to the dark one with the reader's
  system setting, add Shiki's CSS to your stylesheet:

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

Not yet: Markdown directives and components, `sheaf dev` and `sheaf init`.

## License

Sites generated with Sheaf belong entirely to you. Sheaf puts no license, attribution
or branding requirements on your content or on the output it produces.

Sheaf itself is released under the BSD-3-Clause license.
