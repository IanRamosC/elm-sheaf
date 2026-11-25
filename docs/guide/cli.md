# CLI reference

```
Usage: sheaf <command> [options]

Commands:
  sheaf build [--drafts] [--site-url <url>]   Render the site into dist/
  sheaf check [--drafts] [--site-url <url>]   Run every build stage without writing dist/
  sheaf dev [--port <n>]                      Serve the site with drafts, rebuilding on every change
  sheaf init <folder> [--local <path>]        Create a site in an empty or new folder

Options:
  --drafts          Include drafts and documents dated in the future
  --site-url <url>  Use this siteUrl instead of the one in sheaf.json
  --port <n>        Serve on this port instead of the first free one from 4000
  --local <path>    Use a checkout of the Sheaf repository instead of the published packages
  -h, --help        Show this help
  -v, --version     Show the version
```

Inside a site made by `sheaf init`, run the commands with `bunx sheaf`. Until
the packages are published, create a site with the CLI in your clone of this
repository, `bun <clone>/cli/src/index.ts init my-blog --local <clone>`, as
[Getting started](getting-started.md) shows.

`build`, `check` and `dev` run in the site's folder, the one with `sheaf.json`.
An option belongs only to the commands whose usage line shows it: `--drafts`
given to `dev`, which always includes drafts, is a usage error.

## `sheaf build`

Builds the site into `dist/`, leaving out drafts and documents dated after the
moment the build starts.

- `--drafts` includes them.
- `--site-url <url>` builds for this address instead of `siteUrl` in
  `sheaf.json`. It's checked the same way, and a bad value is `BAD CONFIG`.

It prints `Built 7 pages in 0.8s` when it succeeds.

## `sheaf check`

Runs every stage of `sheaf build`, from reading `sheaf.json` to rendering the
pages, without writing `dist/`, and takes the same options. It still updates
the caches in `.sheaf/cache/`, so it decodes every image `build` would.

## `sheaf dev`

Builds the site with drafts, serves it, and rebuilds it whenever something
changes, then reloads the pages open in the browser. It runs until you stop it
with Ctrl-C.

- It serves at `http://127.0.0.1:<port>`, under the site's base path, and
  prints the address. Without `--port` it uses 4000, or the first free port up
  to 4010. `--port <n>` uses exactly that port, and `dev` exits with code 2 if
  it's taken.
- It watches `sheaf.json`, `elm.json`, `content/`, `static/` and the
  `source-directories` of `elm.json`.
- While the latest build has failed, pages show its diagnostics instead, and
  the browser reloads into the site once you fix them.
- It builds into `.sheaf/dev/`, never into `dist/`, and doesn't compile Elm
  with `--optimize`, so `Debug.log` works. Elm's log lines are printed as they
  happen.
- The live reload is a small script `dev` adds to each page as it serves it.
  The built files don't contain it.
- Each open tab holds one live-reload connection. Browsers allow six
  connections per origin over HTTP/1.1, so with more than six tabs open on the
  site, the extra ones stop loading until you close some.
- The base path is read once, when `dev` starts. If you change `siteUrl`'s
  path, `dev` asks you to restart it.

## `sheaf init <folder>`

Creates a site from the starter: a blog with a default theme and a GitHub Pages
workflow. It creates the folder if it's missing, and refuses one with anything
in it, hidden files included, before writing anything. Then it prints the next
steps.

- `--local <path>` makes the site use a clone of this repository instead of the
  published packages: `elm.json` adds the clone's `src` to its
  `source-directories`, and `package.json` depends on the clone's `cli` folder.
  Until the packages are published, this is the only way to make a site that
  builds.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Success, including a build that printed only warnings. Also `--help` and `--version`. |
| 1 | `build` or `check` found errors in the site, or `init` refused the folder or the `--local` path. |
| 2 | The command line is wrong (an unknown command or option, or an option the command doesn't take), Bun is older than 1.4.5, or the port `dev` needs is taken. A usage error prints the help to standard error. |

`sheaf dev` keeps running when a build fails, and exits with 0 when you stop
it.

## Diagnostics

Every problem is printed with a title, the file and position it comes from
when there is one, the source line underlined, and usually a hint:

```
-- UNKNOWN FIELD ---------------------------------- content/posts/welcome.md:4:1

This document has a `sumary` field, but its collection does not declare one.

    4| sumary: What's here, and what to change first.
       ^^^^^^

Did you mean `summary`?
```

A build runs in stages: reading `sheaf.json`, reading the content, parsing the
Markdown and checking its links, highlighting code and processing images,
compiling Elm, rendering the pages, and writing them. Each stage reports every
problem it finds before the build stops, so the next run may find problems in a
later stage. All of them are errors except `CACHE NOT SAVED`, a warning.

Elm compile errors are shown as the Elm compiler writes them, with its own
titles.

### Setting up

| Title | What it means |
|---|---|
| `NO SHEAF.JSON` | There is no `sheaf.json` in the folder the command runs in. |
| `BAD CONFIG` | `sheaf.json` or `--site-url` has a problem: invalid JSON, an unknown key, a missing or invalid `siteUrl`, an unknown timezone or Shiki theme, or bad image settings. |
| `FOLDER NOT EMPTY` | `sheaf init` was given a folder with something in it, or a file. |
| `NOT A SHEAF REPOSITORY` | The `--local` path has no `src/Sheaf.elm` and `cli/package.json`. |
| `ELM NOT FOUND` | There is no `elm` in the site's `node_modules/.bin` or on the `PATH`. |
| `WRONG ELM VERSION` | The `elm` Sheaf found isn't 0.19.3. |
| `BAD ELM JSON` | The site's `elm.json` is missing, can't be read, or isn't a valid JSON object, or the version of `ianramosc/elm-sheaf` isn't a string. |
| `UNSUPPORTED SHEAF VERSION` | `elm.json` depends on a version of `ianramosc/elm-sheaf` outside `1.0.0 <= v < 2.0.0`, or one that isn't `MAJOR.MINOR.PATCH`. |
| `SHEAF PACKAGE MISSING` | `elm.json` has no `ianramosc/elm-sheaf` dependency, and none of its `source-directories` holds `Sheaf.elm`. |
| `SHEAF PACKAGE TWICE` | `elm.json` has the dependency and also a source directory that holds `Sheaf.elm`, as after leaving `--local`. Elm would find every Sheaf module twice. |

### Content and frontmatter

| Title | What it means |
|---|---|
| `BAD COLLECTION NAME` | A folder in `content/` isn't a valid collection name, or is a URL scheme such as `http`. |
| `MISPLACED DOCUMENT` | A Markdown file isn't `<name>.md` or `<name>/index.md` directly inside a collection folder. |
| `UNKNOWN COLLECTION` | A folder in `content/` that no route or feed uses, or a `Collection.named` with no folder. |
| `BAD FRONTMATTER` | The frontmatter isn't valid YAML of `key: value` lines, a reserved key such as `date` or `image` has an invalid value, or a field your decoder reads has the wrong type or fails its validation. |
| `UNKNOWN FIELD` | A frontmatter key the collection's decoder doesn't declare. |
| `MISSING FIELD` | A `required` field is missing. |
| `BAD SLUG` | A file or folder name can't become a URL path segment; set `slug` to fix it. |
| `BAD DATE` | The date at the start of a file name isn't a real date. |
| `MISSING DATE` | A document of a collection listed by date has no date. |
| `DUPLICATE DOCUMENT` | Two documents of a collection have the same slug. |
| `NAME CLASH` | Two slugs of a collection become the same Elm name, or two collection folders the same Elm module. |
| `UNUSABLE SLUG` | A slug has no ASCII letter or digit to make an Elm name from. |

### Markdown and links

| Title | What it means |
|---|---|
| `BROKEN LINK` | A link to a collection or slug that doesn't exist, or to a missing file. |
| `CASE MISMATCH` | A linked file or image exists, but with different capitals, which Linux treats as a different name. |
| `LOCAL FILE LINK` | A link to a file in `content/` that isn't a document, which wouldn't be published. |
| `LINK TO DRAFT` | A published page links to a draft or a future-dated document. |
| `NO PAGE FOR LINK` | A link to a document whose collection has no `Route.eachItem` route, or to a group with no `Route.groupedBy` route for its pattern. |
| `RAW HTML` | The Markdown contains HTML. |
| `UNKNOWN LANGUAGE` | A code block's language isn't one Shiki knows. |
| `UNKNOWN COMPONENT` | A directive names a component the site doesn't declare. |
| `WRONG COMPONENT KIND` | A leaf component is used as a container, or the reverse. |
| `UNKNOWN ATTRIBUTE` | A component attribute the component doesn't declare. |
| `MISSING ATTRIBUTE` | A `required` component attribute is missing. |
| `BAD ATTRIBUTE` | A component attribute's value can't be decoded. |
| `DUPLICATE ATTRIBUTE` | An attribute is written twice; classes are the exception. |
| `DIRECTIVE LABEL` | A component has a `[label]`, which this version doesn't take. |
| `UNCLOSED COMPONENT` | A container component has no closing `:::`. |
| `BAD COMPONENT NAME` | The site declares a component whose name Markdown can't use. |
| `DUPLICATE COMPONENT` | The site declares two components with the same name. |

### Images and static files

| Title | What it means |
|---|---|
| `MISSING IMAGE` | No file at an image's path, or a path that isn't validly percent-encoded. |
| `IMAGE OUTSIDE FOLDER` | An image path leads out of `content/` or `static/`. |
| `UNSUPPORTED IMAGE` | An image in a format Sheaf doesn't publish, or an image URL with a scheme other than `http`, `https` or `data`. |
| `SVG WITHOUT SIZE` | An SVG has neither a `width` and `height` in pixels nor a `viewBox`. |
| `BAD IMAGE` | An image can't be decoded: it isn't an image, it's damaged, or it's too large. |
| `IMAGE NOT READABLE` | An image file can't be read. |
| `CACHE NOT WRITABLE` | `.sheaf/cache/images/` can't be written to. |
| `CACHE NOT SAVED` | A warning: the highlighted code couldn't be cached, so the next build highlights it again. |
| `BROKEN SYMLINK` | A symlink in `static/` leads to nothing. |
| `SYMLINK OUTSIDE SITE` | A symlink in `static/` leads outside the site's folder. |
| `SYMLINK LOOP` | A symlink in `static/` leads to a folder that contains it. |
| `STATIC FILE CLASH` | A file in `static/` has the path of something Sheaf writes, or is under `static/_sheaf/`. |

### Routes, feeds and pages

| Title | What it means |
|---|---|
| `BAD ROUTE` | A route or feed pattern can't be written: no leading `/`, a missing or misplaced `:slug` or `:group`, a path under `/_sheaf/`, or a `perPage` or `limit` below 1. |
| `DUPLICATE PAGE` | Two routes write the same file, compared without regard to case. |
| `NO PAGE FOR FEED` | A feed's collection has no `Route.eachItem` route for its items to link to. |
| `UNKNOWN FEED` | `Head.rssFeed` or `Head.atomFeed` names a feed the site doesn't declare. |
| `MISSING SLUG` | A group value, such as a tag, has no slug, because no document's frontmatter writes it that way. |
| `EMPTY GROUP SLUG` | A group value has no letter or digit to make a slug from. |
| `GROUP COLLISION` | Two different group values, such as `C` and `C++`, have the same slug. |
| `LINK TO EMPTY GROUP` | A link to a group whose documents are all left out of this build. |
| `INVALID HTML` | A template made an element or attribute with an invalid name, a `<script>` or `<style>` element, or used a site path that doesn't start with a single `/`. |

### When something breaks

These point at a bug in Sheaf or in the site's Elm code rather than at the
content. If you think it's Sheaf's, please
[open an issue](https://github.com/IanRamosC/elm-sheaf/issues) with the output.

| Title | What it means |
|---|---|
| `ELM COMPILER FAILED` | `elm make` failed without reporting a compile error. |
| `ELM RUNTIME ERROR` | The compiled site crashed while rendering. |
| `BAD REQUEST` | The Elm package couldn't read what the CLI sent it, which happens when the two come from different versions of Sheaf. |
| `SHEAF CRASHED` | `sheaf dev` caught an unexpected error; it keeps running and builds again on the next change. |
