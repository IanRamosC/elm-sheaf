---
title: Welcome to your blog
date: {{today}}
summary: What's here, and what to change first.
tags: [Sheaf]
---

This post is Markdown in `content/posts/welcome.md`. Sheaf turns it into a
page with the Elm templates in `src/`, and checks every link while it does: a
typed link such as [the about page](pages:about) fails the build if that page
goes away.

## What to edit first

1. Set `siteUrl` in `sheaf.json` to the address the site will live at.
2. Put your title, description and name in `metadata` in `src/Site.elm`.
3. Rewrite `content/pages/about.md`, and replace this post with your own.
4. Change the colours at the top of `static/style.css`, if you like.

:::callout{kind=note}
`bunx sheaf dev` rebuilds the site and reloads the browser whenever you save.
:::

## Code

Code blocks with a language are highlighted when the site is built, so readers
download no JavaScript:

```elm
greet : String -> String
greet name =
    "Hello, " ++ name ++ "!"
```

## Older and newer posts

A post with three or more sections, like this one, starts with a list of them,
and every post ends with links to the posts written before and after it. Each
heading has a `#` link to itself, shown when you point at the heading, for
sharing one section.
