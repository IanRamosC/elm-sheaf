---
title: Sheaf
description: A static site generator whose templates are written in Elm.
---

Sheaf builds a website from Markdown files and templates written in Elm. A
template is a typed function from a document to a page, so the compiler
checks the templates against the types of the frontmatter. The build stops at
a missing field or a broken link, and points at the line.

Create a blog and run it:

```sh
bunx elm-sheaf init my-blog
cd my-blog
bun install
bunx sheaf dev
```

Sheaf isn't published yet. Until 1.0, [create a site from a
clone](../guide/getting-started.md#before-the-first-release).

- Frontmatter is typed, and [links are checked](guide:content) when the site
  is built.
- The pages [have no JavaScript](guide:deploying).
- A [blog preset](guide:templates) comes with feeds and images.
- [Get started](guide:getting-started) with a blog from the starter.
