---
title: Sheaf
description: A static site generator whose templates are written in Elm.
---

Sheaf builds a website from Markdown files and templates written in Elm. A
template is a typed function from a document to a page, so the compiler
catches a missing field or a broken link before the site is built.

Create a blog and run it:

```sh
bunx elm-sheaf init my-blog
cd my-blog
bun install
bunx sheaf dev
```

- [Get started](guide:getting-started) with a blog from the starter.
- Learn how [content](guide:content) and [templates](guide:templates) fit
  together.
- [Deploy](guide:deploying) the built site to GitHub Pages or any static host.
