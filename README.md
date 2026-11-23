# Sheaf

Sheaf is a static site generator whose templates are written in Elm. You describe
your site's pages as typed Elm functions, keep your content in Markdown with
frontmatter, and Sheaf renders the whole site to plain HTML files.

The repository holds two packages:

- the root is the Elm package `ianramosc/elm-sheaf`, the library your templates import;
- `cli/` is the npm package `elm-sheaf`, the Bun and TypeScript host that builds the site.

Sites generated with Sheaf belong entirely to you. Sheaf puts no license, attribution
or branding requirements on your content or on the output it produces.

Sheaf itself is released under the BSD-3-Clause license.
