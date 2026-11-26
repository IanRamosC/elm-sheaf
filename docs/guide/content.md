# Content

Content is Markdown with YAML frontmatter, kept in `content/`. This page covers
how Sheaf finds documents, what it reads from their frontmatter, when a
document is published, and how documents link to each other.

## Collections

Every folder directly inside `content/` is a collection, named after the
folder. A blog has two: `content/posts/` and `content/pages/`.

A collection's name is lowercase letters, digits and hyphens, starting with a
letter. It can't be a URL scheme such as `http` or `mailto`, because
`<collection>:<slug>` is how Markdown links to a document. Any other name is
`BAD COLLECTION NAME`.

Inside a collection, a document is either a file or a folder:

```
content/posts/
  2026-11-23-hello-world.md
  2026-11-19-pictures/
    index.md
    cover.png
    photo.png
```

The folder form keeps a document's images next to it. Anything else, such as a
Markdown file directly in `content/` or nested deeper, is `MISPLACED DOCUMENT`.

Every collection folder must be declared in Elm with `Collection.named`, and
every declared collection must have a folder; either mismatch is
`UNKNOWN COLLECTION`. Git doesn't keep empty folders, so commit an empty
`.gitkeep` in a collection that has no documents yet. `sheaf init` writes one
in `content/posts/` and `content/pages/`.

## Frontmatter

Frontmatter is YAML between two `---` lines at the top of the file:

```markdown
---
title: Pictures and code
summary: A cover, a photo, a callout and some Elm.
tags: [Elm]
image: { src: cover.png, alt: Cover }
---
```

Six keys are reserved: Sheaf reads them itself, before any Elm runs.

| Key | What it is | When it's missing |
|---|---|---|
| `slug` | The document's name in URLs and links | Taken from the file or folder name |
| `date` | When the document is published | Taken from a `YYYY-MM-DD-` prefix of the name, if there is one |
| `updated` | When it last changed significantly | None; feeds use `date` |
| `draft` | `true` keeps it out of production builds | `false` |
| `image` | A cover image, for the layout and link previews | None |
| `aliases` | Old paths that redirect to the document | None |

A reserved key with a value of the wrong kind, such as `draft: yes`, is
`BAD FRONTMATTER`. The `image` key is covered in
[Static files and images](static-files-and-images.md), and `aliases` in
[Old URLs](#old-urls). Templates don't see `aliases`.

Every other key belongs to your collection's decoder, written with
`Sheaf.Frontmatter`. This one is from the starter's `src/Site.elm`:

```elm
postFrontmatter : Frontmatter PostMeta
postFrontmatter =
    Frontmatter.succeed PostMeta
        |> Frontmatter.required "title" Frontmatter.string
        |> Frontmatter.optional "summary" Frontmatter.string
        |> Frontmatter.withDefault "tags" [] (Frontmatter.list Frontmatter.string)
```

Unlike a `Json.Decode.Decoder`, a `Frontmatter` knows every field it reads, so
a key it doesn't declare is an error rather than something quietly ignored:

- a key the decoder doesn't declare is `UNKNOWN FIELD`, with a suggestion when
  it's close to one it does;
- a `required` field that is missing is `MISSING FIELD`;
- a value of the wrong type is `BAD FRONTMATTER`, underlined in the file.

Sheaf reports all of these at once, for every document.

## Slugs

A document's slug comes from its file name without `.md`, or from its folder's
name, after dropping a leading date: `2026-11-23-hello-world.md` has the slug
`hello-world`. Set `slug` in the frontmatter to choose another.

A slug is one URL path segment. It can't contain `/`, `\`, spaces, control
characters, `#`, `?` or `%`. A file name that breaks this is `BAD SLUG`, and a
`slug` value that breaks it is `BAD FRONTMATTER`. Two documents of a collection with the same slug are
`DUPLICATE DOCUMENT`.

Sheaf generates an Elm module per collection, with a value per document, so
templates can link to documents by name (see [Templates](templates.md)). The
slug becomes the value's name: `hello-world` becomes
`Content.Posts.helloWorld`, and `2026-recap` becomes `n2026Recap`. Two slugs
that become the same name are `NAME CLASH`, and a slug with no ASCII letter or
digit, which can't become one, is `UNUSABLE SLUG`. Setting `slug` fixes both.

## Old URLs

When a document moves, list the paths it used to have under `aliases`, and
Sheaf writes a page at each one that sends readers on to the new one:

```yaml
aliases:
  - /2019/03/old-post-name/
  - /old.html
```

A single path can be written without the list, as `aliases: /old/`.

Each alias is a path on this site, starting with `/` and without the base
path, which Sheaf adds. Its segments follow the rules for slugs, so it can't
have a query, a fragment, a `.` or `..` segment, or two slashes in a row. Write
characters such as `é` as they are rather than percent-encoded. It can't be in
`/_sheaf/`, or be `/robots.txt` or `/sitemap.xml`, which Sheaf writes itself.
An alias that breaks these rules is `BAD ALIAS`.

An alias ending in `.html`, in any case, is written as that file. Any other is a folder with
an `index.html`, so `/old` and `/old/` are the same page. A server would send a
file without an extension as something other than HTML, and the redirect
wouldn't work.

The redirect page uses a meta refresh, which works on any static host. It
names the new page as canonical, asks search engines not to index the old one,
and links to the new page for browsers that don't follow the refresh. A meta
refresh can't carry a fragment over, so `/old/#setup` lands at the top of the
new page.

Redirect pages aren't in the sitemap or the feeds. The rules for them:

- the document's collection needs a `Route.eachItem` route, or there is no
  page to redirect to; without one, the alias is `ALIAS WITHOUT PAGE`;
- an alias that would be written where another page, alias or feed is, is
  `DUPLICATE PAGE`, and one where a file of `static/` is, is
  `STATIC FILE CLASH`;
- a draft left out of the build has its aliases left out too.

## Dates and drafts

A document's date is its `date` key, or else the date its file or folder name
starts with. Write it as `YYYY-MM-DD`, or as a timestamp with an offset such as
`2026-11-30T10:00:00+02:00`. A date alone means midnight at the start of that
day in the site's `timezone` (see [Configuration](configuration.md)), which is
UTC unless you set it. An impossible date, such as `2026-02-30`, is `BAD DATE`
in a file name and `BAD FRONTMATTER` in the frontmatter.

A collection that some route lists by date, such as the blog's posts, needs a
date on every document. One without is `MISSING DATE`. Documents that are only
rendered one per page, such as the blog's pages, don't need one, and nor do
those of a collection ordered by a number (see
[Templates](templates.md#ordering-by-a-number)).

A document is left out of `sheaf build` when it has `draft: true`, or when its
date is later than the moment the build starts. `sheaf dev` includes both, and
so does `sheaf build --drafts`. A post dated next week is published by the
first build after its date, so a scheduled post needs a build on or after that
day.

A published document that links to a left-out one is `LINK TO DRAFT`: publish
the target too, or remove the link.

## Links between documents

A Markdown link to another document is written `<collection>:<slug>`, and may
carry a fragment:

```markdown
Jump to [the top](posts:hello-world#top) of this post.
```

Sheaf checks it before anything is rendered. A collection or slug that doesn't
exist is `BROKEN LINK`, with suggestions:

```
Did you mean one of these?

    pages:about
```

A link may also be the path of the other document's Markdown file. A relative
path such as `../pages/about.md` is read from the linking document's folder,
and one starting with `/`, such as `/pages/about.md`, from `content/`. Both are
checked the same way.

Other relative links are checked against the files in `content/` too:

- a link to a file that exists but isn't a document, such as `./notes.pdf`, is
  `LOCAL FILE LINK`, because only documents are published from `content/`.
  Put the file in `static/` and link to it with a path starting with `/`;
- a link to a missing file with an extension is `BROKEN LINK`;
- a file name that matches only when case is ignored is `CASE MISMATCH`, since
  the site would build on macOS but not on Linux.

A relative path without an extension (`../archive/`), a path starting with `/`
that doesn't end in `.md`, and URLs with a scheme (`https:`, `mailto:`) aren't
checked. Fragments aren't checked either.

A document link becomes a URL when Elm renders the page, so the target's
collection needs a `Route.eachItem` route that gives each of its documents a
page. Without one, the link is `NO PAGE FOR LINK`.

## Markdown

Sheaf parses Markdown with [micromark](https://github.com/micromark/micromark),
following CommonMark and GitHub Flavored Markdown: tables, task lists,
footnotes, strikethrough and autolinks work. Headings get ids the way GitHub
makes them, lowercase with spaces as hyphens, so `## What to edit first` can be
linked as `#what-to-edit-first`.

Each heading also ends with a link to itself, so readers can copy a link to
that section:

```html
<h2 id="setup">Setup <a class="heading-link" href="#setup" aria-labelledby="setup">#</a></h2>
```

Style it with the `heading-link` class. The `#` is only decoration: screen
readers name the link by the heading's text. A heading with no letters or
digits, such as `## !!!`, gets no link. Feeds leave these links out, because
feed readers would show a stray `#`. Templates get a document's headings too,
for a table of contents; see [Templates](templates.md#pages).

Raw HTML in Markdown is `RAW HTML`. Sheaf's output contains only what your
templates produce, so use a component instead.

### Code blocks

Every fenced code block is highlighted when the site is built, with
[Shiki](https://shiki.style/), so readers download no JavaScript for it:

````markdown
```elm
greet : String -> String
greet name =
    "Hello, " ++ name ++ "!"
```
````

A block without a language is plain text. A language Sheaf can't highlight is
`UNKNOWN LANGUAGE`, with a suggestion; names are case-sensitive, as in Shiki.
Use `text` for a block you don't want highlighted. Sheaf leaves out Shiki's
`ada`, `gnuplot`, `nginx`, `org` and `racket` grammars, because they are
GPL-3.0 and Sheaf is BSD-3-Clause, but a site can
[add them back](configuration.md#your-own-grammars-and-themes), as it can any
other grammar. The themes are set in
[Configuration](configuration.md#highlight).

### Components

A component is a Markdown directive rendered by an Elm view you write. A
container wraps Markdown and ends with a line of `:::`:

```markdown
:::callout{kind=note}
`bunx sheaf dev` rebuilds the site and reloads the browser whenever you save.
:::
```

A leaf is a single line, `::name{…}`. Attributes go in the braces, quoted or
not: `kind=note` and `kind="note"` are the same. `#x` is short for `id=x`, and
`.y` adds a class.

Components are declared in Elm, as [Templates](templates.md#components)
shows, and every use is checked against them:

- a name the site doesn't declare is `UNKNOWN COMPONENT`, and a leaf used as a
  container, or the reverse, is `WRONG COMPONENT KIND`;
- `UNKNOWN ATTRIBUTE`, `MISSING ATTRIBUTE` and `BAD ATTRIBUTE` name the
  attribute and what it should be;
- an attribute written twice is `DUPLICATE ATTRIBUTE`, except classes, which
  add up;
- a label, as in `::name[text]`, is `DIRECTIVE LABEL` in this version: pass
  the text as an attribute;
- a container with no closing `:::` is `UNCLOSED COMPONENT`, since it would
  take in the rest of the document.

The inline form, `:name[…]`, isn't a component in this version, so text such as
`12:30` or `foo:bar` is never mistaken for one.
