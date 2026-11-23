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

## License

Sites generated with Sheaf belong entirely to you. Sheaf puts no license, attribution
or branding requirements on your content or on the output it produces.

Sheaf itself is released under the BSD-3-Clause license.
