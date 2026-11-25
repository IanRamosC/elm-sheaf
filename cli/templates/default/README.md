# My blog

A blog built with [Sheaf](https://github.com/IanRamosC/elm-sheaf): posts in
Markdown, templates in Elm, and plain HTML and CSS as the result.

## Commands

```sh
bun install          # once, after cloning
bunx sheaf dev       # serve the site with drafts, rebuilding as you save
bunx sheaf build     # write the published site to dist/
bunx sheaf check     # check everything without writing the site
```

## Where things are

- `content/posts/` holds the posts and `content/pages/` the other pages, such
  as `about.md`.
- `src/Site.elm` holds the site's title, author and frontmatter; the templates
  are in `src/Theme/`.
- `static/` is copied into the site as it is. `static/style.css` is the only
  stylesheet.
- `sheaf.json` holds the address of the site, `siteUrl`.

## Publishing

### GitHub Pages

In the repository's Settings → Pages, choose "GitHub Actions" as the source,
then push to `main`. The workflow in `.github/workflows/deploy.yml` builds the
site with the address GitHub gives it, so `siteUrl` needn't match.

### Netlify and Cloudflare Pages

Use the build command `bunx sheaf build --site-url <your URL>` and the output
directory `dist`.

## Licence

This starter is offered under the 0BSD licence: use it however you like, with
no notice required. Your site and everything you write in it are yours.
