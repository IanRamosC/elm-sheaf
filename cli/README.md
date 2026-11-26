# Sheaf

Static sites with templates in Elm.

Sheaf is a static site generator for Elm developers who want a blog, or a
small site of their own, without an application framework. Your content is
Markdown with frontmatter, your pages are typed Elm functions, and the result
is a folder of plain HTML and CSS with no JavaScript in it. The build fails,
with a message that points at the line, on a misspelled frontmatter field, a
link to a document that doesn't exist, or an image that isn't there.

## Status

Sheaf is not released yet. Neither the npm package `elm-sheaf` nor the Elm
package `ianramosc/elm-sheaf` is published, and there are no binaries to
download, so the steps below don't work yet. For now, run the CLI from a clone
of the repository and create sites with `--local`, which points them at that
clone. Expect the API to change before the first release. The
[repository README](https://github.com/IanRamosC/elm-sheaf#status) explains
how to try it today.

## Requirements

- [Bun](https://bun.sh) 1.4.5 or newer.
- [Elm 0.19.3](https://guide.elm-lang.org/install/elm.html). A site made by
  `sheaf init` has Elm in its `package.json`, so `bun install` usually provides
  it.

## Quick start

```sh
bunx elm-sheaf init my-blog
cd my-blog
bun install
bunx sheaf dev
```

The package provides the command `sheaf`, also available as `elm-sheaf`, so
that `bunx elm-sheaf` works without installing anything first. Inside a site,
`sheaf dev` serves it and reloads the browser on every save, `sheaf build`
renders it into `dist/`, and `sheaf check` reports problems without writing
anything.

## Without Bun

Each [release](https://github.com/IanRamosC/elm-sheaf/releases) has a
standalone binary for macOS, Linux and Windows, which needs no Bun, only Elm
0.19.3 on your `PATH`.
[Getting started](https://github.com/IanRamosC/elm-sheaf/blob/main/docs/guide/getting-started.md#install-sheaf)
says which file to download and how to install it on each system.

## Documentation

The [repository README](https://github.com/IanRamosC/elm-sheaf#readme) and its
[guide](https://github.com/IanRamosC/elm-sheaf/blob/main/docs/guide/getting-started.md)
cover the content format, templates, configuration and deployment.

## Licence

BSD-3-Clause. Sites you generate belong entirely to you.
