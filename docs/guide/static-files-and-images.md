# Static files and images

## Static files

Everything in `static/` is copied into the site as it is, at the same path:
`static/style.css` is served at `/style.css`, and `static/robots.txt` at
`/robots.txt`. Hidden files are copied too, so `static/.well-known/` works.
Use it for stylesheets, fonts, a favicon, and files you link to, such as a PDF.

The starter's `static/favicon.svg` is Sheaf's logo, linked from every page by
`Head.icon { path = "/favicon.svg", mediaType = "image/svg+xml" }` in
`src/Theme/Layout.elm`. Replace the file with your own icon; for a PNG or ICO,
change the path and the media type to match.

Symlinks in `static/` are followed only while they stay inside the site's
folder, because everything in `static/` is published and a link out of it
could publish a file from whichever machine builds the site. A link that leads
outside is `SYMLINK OUTSIDE SITE`, one to a missing file is `BROKEN SYMLINK`,
and one to a folder that contains it is `SYMLINK LOOP`.

A static file can't take the place of something Sheaf writes. A file at the
same path as a page, a feed, the sitemap or an image, or a file where Sheaf
needs a folder, is `STATIC FILE CLASH`, naming both. Paths are compared without
regard to case. Anything under `static/_sheaf/` clashes, since Sheaf keeps that
folder for its own files.

## robots.txt

Every build writes a `robots.txt` that lets crawlers read the whole site and
names the sitemap:

```
User-agent: *
Allow: /

Sitemap: https://example.com/sitemap.xml
```

It is a default. To replace it, put your own at `static/robots.txt`, or write
one from a route at `/robots.txt`; Sheaf then leaves its own out and reports
nothing, so this is not a `STATIC FILE CLASH`. A file you write yourself should
name the sitemap too, because Sheaf no longer does.

Crawlers only read `/robots.txt` at the root of a domain. With a base path, such
as `https://example.com/blog/`, Sheaf still writes the file inside it, next to
the sitemap, but it only takes effect when the site is served at the root of its
domain.

## Images in Markdown

A Markdown image whose path is a local file is resized and encoded when the site
is built. From the `blog` fixture's `content/posts/2026-11-19-pictures/index.md`:

```markdown
![A photo](photo.png)
```

A relative path is read from the document's folder, which is why a post with
images is a folder with an `index.md`. It must stay inside `content/`. A path
starting with `/` is read from `static/`, so `/logo.png` is
`static/logo.png`, and must stay inside `static/`. Anything else is
`IMAGE OUTSIDE FOLDER`.

A path to a file that doesn't exist is `MISSING IMAGE`, with a suggestion when
a file has a similar name. A path that matches a file only when case is ignored
is `CASE MISMATCH`, because macOS would find the file and Linux wouldn't.

`http:`, `https:`, `//` and `data:` images are left as written, without any
processing.

### What Sheaf writes

Each local JPEG, PNG or WebP image is written at several widths: every width in
`images.widths` smaller than the image, plus the image's own width or the
largest configured width, whichever is smaller. Nothing is enlarged. Each width
is written in the image's own format and as WebP (see
[Configuration](configuration.md#images)).

The files go to `/_sheaf/images/`, named from a hash of the image and the
encoder, and the image becomes a `<picture>` with its width and height, so the
page doesn't move while it loads. With the default widths, the 1200-pixel PNG
above becomes:

```html
<picture><source type="image/webp" srcset="/blog/_sheaf/images/6408dc9e106f009b-480.webp 480w, /blog/_sheaf/images/6408dc9e106f009b-960.webp 960w, /blog/_sheaf/images/6408dc9e106f009b-1200.webp 1200w" sizes="(min-width: 1200px) 1200px, 100vw"><img src="/blog/_sheaf/images/6408dc9e106f009b-1200.png" srcset="/blog/_sheaf/images/6408dc9e106f009b-480.png 480w, /blog/_sheaf/images/6408dc9e106f009b-960.png 960w, /blog/_sheaf/images/6408dc9e106f009b-1200.png 1200w" sizes="(min-width: 1200px) 1200px, 100vw" width="1200" height="800" alt="A photo" loading="lazy" decoding="async"></picture>
```

The `blog` fixture is served under `/blog/`, which is why every path starts
with it.

GIF and SVG images are copied unchanged, so animations survive, and still get
their width and height. An SVG's size comes from its `width` and `height` in
pixels, or else from its `viewBox`; one with neither is `SVG WITHOUT SIZE`.
Another format that Bun can read is `UNSUPPORTED IMAGE`, and a file that
can't be decoded is `BAD IMAGE`.

Only the images of documents in the build are written, so a draft's images
never reach `dist/`. Their problems are still reported, and `sheaf check`
decodes every image, so it catches what `sheaf build` would.

### The cache

Encoding is slow, so encoded images are kept in `.sheaf/cache/images/` and
reused while the image and the encoder stay the same. The folder is safe to
delete. A source image that can't be read is `IMAGE NOT READABLE`, and a cache
folder that can't be written is `CACHE NOT WRITABLE`, since a variant the page
needs can't be skipped.

Highlighted code is cached in `.sheaf/cache/highlight.json`. If that file can't
be saved, the build goes on with a `CACHE NOT SAVED` warning, and the next
build highlights the code again.

## Cover images

The reserved frontmatter key `image` gives a document a cover. It is processed
like a Markdown image, and its problems point at the key:

```markdown
image: { src: cover.png, alt: Cover }
```

`image: cover.png` works too, with empty alt text. A remote cover must be an
`http` or `https` URL, because link previews need a full address; `//` and
`data:` covers are `BAD FRONTMATTER`.

Templates get the cover as `document.image`, a `Maybe Image`. `Image.view`
renders it as above, and `Image.src` gives the path link previews need. From
the starter's post template:

```elm
cover : Document meta -> Html
cover document =
    case document.image of
        Just image ->
            -- The cover is at the top of the page, where lazy loading only delays it.
            Image.view [ attribute "loading" "eager" ] image

        Nothing ->
            text ""
```

`Image.width` and `Image.height` are `Maybe Int`, because a remote image has no
known size.

## Images in templates

Templates can't process images in this version. An image used by a template,
such as a logo, is a file in `static/`, linked with `siteSrc` so the base path
is added:

```elm
img [ siteSrc "/cover.png" ] []
```

It is published as it is, without resizing.
