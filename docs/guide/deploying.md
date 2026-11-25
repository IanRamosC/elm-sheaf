# Deploying

`sheaf build` writes the whole site to `dist/`: HTML, CSS, images, feeds and
`sitemap.xml`, with no JavaScript and nothing that needs a server. Any host
that serves static files can serve it. Drafts and future-dated documents are
never in `dist/`.

## Before the packages are published

A site made with `sheaf init --local` depends on your clone of Sheaf by its
absolute path, in both `package.json` and `elm.json`. A build server doesn't
have that clone, so the setups below can't build such a site yet: `bun install`
fails there. Until the packages are published, build on your machine and upload
`dist/` with your host's own tools. If you push the site to GitHub, delete or
disable the starter's `.github/workflows/deploy.yml`, which would otherwise fail
on every push to `main`:

```sh
bunx sheaf build --site-url https://example.com/
```

The rest of this page describes how a site deploys once `bun install` works on
the host.

## Choosing the address

Feeds, the sitemap, canonical URLs and link previews need the site's full
address, which is `siteUrl` in `sheaf.json`. `--site-url` replaces it for one
build, so the address can come from the host instead of the file (see
[Configuration](configuration.md#siteurl)). A site served under a path, such as
`https://example.com/blog/`, is built for that path.

## GitHub Pages

The starter includes `.github/workflows/deploy.yml`. It runs on every push to
`main`, and from the Actions tab, and does the following:

1. installs the newest Bun and runs `bun install`;
2. asks GitHub for the site's address with `actions/configure-pages`;
3. runs `bunx sheaf build --site-url "<that address>/"`;
4. uploads `dist/`, hidden files included, so `static/.well-known/` survives;
5. deploys it with `actions/deploy-pages`.

To turn it on, open the repository's Settings, then Pages, and choose "GitHub
Actions" as the source. Push to `main`. Because the workflow passes GitHub's
address to `--site-url`, the site works at `https://<user>.github.io/<repository>/`
without changing `sheaf.json`; set `siteUrl` anyway, for the builds you run
yourself.

GitHub Pages serves `404.html` for addresses with no page.

## Netlify and Cloudflare Pages

Set the build command and the output directory in the host's settings for the
site:

- build command: `bunx sheaf build --site-url <your URL>`
- output directory: `dist`

The host must provide Bun 1.4.5 or newer; Sheaf stops with an upgrade message
on an older one. Both hosts serve `404.html` for addresses with no page.
