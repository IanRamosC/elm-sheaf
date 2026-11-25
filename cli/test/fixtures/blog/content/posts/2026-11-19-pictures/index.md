---
title: Pictures and code
summary: A cover, a photo, a callout and some Elm.
tags: [Elm]
image: { src: cover.png, alt: Cover }
---

Every image is published in several widths.

![A photo](photo.png)

:::callout{kind="note"}
Each post is in the feeds too, as [the feeds post](posts:feeds) explains.
:::

```elm
isSmall : Int -> Bool
isSmall count =
    0 < count && count < 10
```
