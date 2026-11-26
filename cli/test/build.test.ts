import { afterEach, describe, expect, test } from "bun:test";
import {
  chmodSync,
  cpSync,
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  realpathSync,
  renameSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { join, relative, resolve, sep } from "node:path";
import { type BuildOptions, build } from "../src/build";
import { imageHash } from "../src/images/codec";
import { initSite } from "../src/init/init";
import {
  copyFixture,
  fixturePath,
  removeFixtureCopies,
} from "./support/fixtures";
import { pngBytes } from "./support/images";
import { permissionsApply } from "./support/permissions";

// The first compile of a site can take several seconds.
const SLOW = 60_000;
const now = new Date("2026-12-01T00:00:00Z");

afterEach(removeFixtureCopies);

function titlesOf(result: Awaited<ReturnType<typeof build>>): string[] {
  return result.ok ? [] : result.error.map(({ title }) => title);
}

function options(root: string, overrides: Partial<BuildOptions> = {}) {
  return {
    mode: "production",
    now,
    output: join(root, "dist"),
    optimize: true,
    log: () => {},
    ...overrides,
  } satisfies BuildOptions;
}

function clean(root: string) {
  rmSync(join(root, "dist"), { recursive: true, force: true });
}

describe("build", () => {
  test(
    "writes the pages and copies static files",
    async () => {
      const root = fixturePath("minimal");
      clean(root);

      const result = await build(root, options(root));

      expect(result.ok && result.value.pages).toBe(1);
      expect(existsSync(join(root, "dist/posts/hello-world/index.html"))).toBe(
        true,
      );
      expect(readFileSync(join(root, "dist/robots.txt"), "utf8")).toContain(
        "User-agent",
      );
    },
    SLOW,
  );

  test(
    "counts redirects apart from pages",
    async () => {
      const root = copyFixture("minimal");
      writeFileSync(
        join(root, "content/posts/2026-11-23-hello-world.md"),
        "---\ntitle: Hello, world\naliases:\n  - /old/\n---\n\nHi.\n",
      );

      const result = await build(root, options(root));

      expect(titlesOf(result)).toEqual([]);
      expect(result.ok && [result.value.pages, result.value.redirects]).toEqual(
        [1, 1],
      );
    },
    SLOW,
  );

  describe("robots.txt", () => {
    const sitemapLine = "Sitemap: https://example.com/blog/sitemap.xml";

    /** Adds a route at `path` to the minimal site; its page says `mine`. */
    function addRoute(root: string, path: string) {
      const file = join(root, "src/Site.elm");
      writeFileSync(
        file,
        readFileSync(file, "utf8")
          .replace(
            "import Sheaf.Route as Route",
            "import Sheaf.Html exposing (text)\nimport Sheaf.Route as Route",
          )
          .replace(
            "[ Route.eachItem",
            `[ Route.single "${path}" { title = "Mine", head = [], body = [ text "mine" ] }\n            , Route.eachItem`,
          ),
      );
    }

    test(
      "is written when the site has none, naming the sitemap",
      async () => {
        const root = copyFixture("blog");
        rmSync(join(root, "static/robots.txt"), { force: true });

        const result = await build(root, options(root));

        expect(titlesOf(result)).toEqual([]);
        expect(readFileSync(join(root, "dist/robots.txt"), "utf8")).toBe(
          `User-agent: *\nAllow: /\n\n${sitemapLine}\n`,
        );
      },
      SLOW,
    );

    test(
      "gives way to a static robots.txt without a diagnostic",
      async () => {
        const root = copyFixture("minimal");

        const result = await build(root, options(root));

        expect(titlesOf(result)).toEqual([]);
        expect(readFileSync(join(root, "dist/robots.txt"), "utf8")).toBe(
          readFileSync(join(root, "static/robots.txt"), "utf8"),
        );
      },
      SLOW,
    );

    test(
      "gives way to a static file with another case",
      async () => {
        const root = copyFixture("minimal");
        renameSync(
          join(root, "static/robots.txt"),
          join(root, "static/Robots.txt"),
        );

        const result = await build(root, options(root));

        expect(titlesOf(result)).toEqual([]);
        const robots = readdirSync(join(root, "dist")).filter(
          (name) => name.toLowerCase() === "robots.txt",
        );
        expect(robots).toEqual(["Robots.txt"]);
      },
      SLOW,
    );

    test(
      "gives way to a route's robots.txt",
      async () => {
        const root = copyFixture("minimal");
        rmSync(join(root, "static/robots.txt"));
        addRoute(root, "/robots.txt");

        const result = await build(root, options(root));

        expect(titlesOf(result)).toEqual([]);
        expect(readFileSync(join(root, "dist/robots.txt"), "utf8")).toContain(
          "mine",
        );
      },
      SLOW,
    );

    test(
      "is not written when a route's output is a folder named robots.txt",
      async () => {
        const root = copyFixture("minimal");
        rmSync(join(root, "static/robots.txt"));
        addRoute(root, "/robots.txt/");

        const result = await build(root, options(root));

        expect(titlesOf(result)).toEqual([]);
        expect(statSync(join(root, "dist/robots.txt")).isDirectory()).toBe(
          true,
        );
      },
      SLOW,
    );
  });

  test(
    "reports every broken link and writes nothing",
    async () => {
      const root = fixturePath("broken-links");
      clean(root);

      const result = await build(root, options(root));

      expect(titlesOf(result)).toEqual(["BROKEN LINK", "BROKEN LINK"]);
      expect(existsSync(join(root, "dist"))).toBe(false);
      // The language server needs the references while the author fixes links.
      expect(existsSync(join(root, ".sheaf/gen/SheafMain.elm"))).toBe(true);
    },
    SLOW,
  );

  test(
    "renders a draft only in drafts mode",
    async () => {
      const root = fixturePath("drafts");
      const draftPage = join(root, "dist/posts/work-in-progress/index.html");

      clean(root);
      const production = await build(root, options(root));
      expect(production.ok).toBe(true);
      expect(existsSync(join(root, "dist/posts/hello-world/index.html"))).toBe(
        true,
      );
      expect(existsSync(draftPage)).toBe(false);

      clean(root);
      const withDrafts = await build(root, options(root, { mode: "drafts" }));
      expect(withDrafts.ok).toBe(true);
      expect(existsSync(draftPage)).toBe(true);
    },
    SLOW,
  );

  test(
    "rejects a link to a draft in production",
    async () => {
      const root = copyFixture("drafts");
      writeFileSync(
        join(root, "content/posts/2026-11-25-linker.md"),
        "---\ntitle: Linker\n---\n\nSee [the draft](posts:work-in-progress).\n",
      );

      const result = await build(root, options(root));

      expect(titlesOf(result)).toEqual(["LINK TO DRAFT"]);
    },
    SLOW,
  );

  test(
    "logs what the worker prints, and Elm still reports a link to a draft",
    async () => {
      const root = copyFixture("drafts");
      const site = join(root, "src/Site.elm");
      writeFileSync(
        site,
        readFileSync(site, "utf8")
          .replace("import Sheaf\n", "import Content.Posts\nimport Sheaf\n")
          .replace(
            "body = post.body }",
            'body = Debug.log "rendering" post.body ++ [ Sheaf.link Content.Posts.workInProgress [] ] }',
          ),
      );
      const lines: string[] = [];

      const result = await build(
        root,
        options(root, {
          optimize: false,
          log: (line) => lines.push(line),
        }),
      );

      expect(titlesOf(result)).toEqual(["LINK TO DRAFT"]);
      expect(lines.some((line) => line.startsWith("rendering:"))).toBe(true);
    },
    SLOW,
  );

  test(
    "check encodes images into the cache but writes no dist",
    async () => {
      const root = copyFixture("minimal");
      writeFileSync(
        join(root, "content/posts/2026-11-23-hello-world.md"),
        "---\ntitle: Hello, world\n---\n\n![A photo](photo.png)\n",
      );
      writeFileSync(join(root, "content/posts/photo.png"), pngBytes(600, 400));

      const result = await build(root, options(root, { output: undefined }));

      expect(titlesOf(result)).toEqual([]);
      expect(result.ok).toBe(true);
      expect(readdirSync(join(root, ".sheaf/cache/images"))).toHaveLength(4);
      expect(existsSync(join(root, "dist"))).toBe(false);
    },
    SLOW,
  );

  test(
    "publishes the images of published documents only, but checks a draft's",
    async () => {
      const root = copyFixture("drafts");
      const draft = join(root, "content/posts/2026-11-24-work-in-progress.md");
      writeFileSync(
        draft,
        readFileSync(draft, "utf8").replace(/\n*$/, "\n\n![x](draft.png)\n"),
      );
      writeFileSync(
        join(root, "content/posts/2026-11-25-shown.md"),
        "---\ntitle: Shown\n---\n\n![x](shown.png)\n",
      );
      writeFileSync(join(root, "content/posts/shown.png"), pngBytes(300, 200));

      expect(titlesOf(await build(root, options(root)))).toEqual([
        "MISSING IMAGE",
      ]);

      writeFileSync(join(root, "content/posts/draft.png"), pngBytes(200, 100));
      const result = await build(root, options(root));

      expect(titlesOf(result)).toEqual([]);
      expect(result.ok).toBe(true);
      const published = readdirSync(join(root, "dist/_sheaf/images")).sort();
      expect(published.map((name) => name.replace(/^.*-/, ""))).toEqual([
        "300.png",
        "300.webp",
      ]);
    },
    SLOW,
  );

  test(
    "check compiles and renders but writes no dist",
    async () => {
      const root = fixturePath("minimal");
      clean(root);

      const result = await build(root, options(root, { output: undefined }));

      expect(result.ok && result.value.pages).toBe(1);
      expect(existsSync(join(root, "dist"))).toBe(false);
    },
    SLOW,
  );

  test(
    "reports a static file that would replace the feed, and writes no dist",
    async () => {
      const root = copyFixture("blog");
      writeFileSync(join(root, "static/feed.xml"), "mine");

      const built = await build(root, options(root));
      const checked = await build(root, options(root, { output: undefined }));

      for (const result of [built, checked]) {
        expect(result.ok ? [] : result.error).toMatchObject([
          {
            title: "STATIC FILE CLASH",
            message:
              "static/feed.xml would replace the feed.xml that Sheaf generates.",
          },
        ]);
      }
      expect(existsSync(join(root, "dist"))).toBe(false);
    },
    SLOW,
  );

  test(
    "highlights code and caches the tokens",
    async () => {
      const root = copyFixture("minimal");
      writeFileSync(
        join(root, "content/posts/2026-11-24-code.md"),
        '---\ntitle: Code\n---\n\n```elm\nmain = text "<&>"\n```\n',
      );

      const result = await build(root, options(root));

      expect(titlesOf(result)).toEqual([]);
      const page = readFileSync(
        join(root, "dist/posts/code/index.html"),
        "utf8",
      );
      expect(page).toContain('<pre class="shiki" style="background-color:');
      expect(page).toContain("&quot;&lt;&amp;&gt;&quot;</span>");
      expect(existsSync(join(root, ".sheaf/cache/highlight.json"))).toBe(true);
    },
    SLOW,
  );

  test(
    "reports an unknown language in a draft too",
    async () => {
      const root = copyFixture("minimal");
      writeFileSync(
        join(root, "content/posts/2026-11-24-code.md"),
        "---\ntitle: Code\ndraft: true\n---\n\n```elmm\nx = 1\n```\n",
      );

      const result = await build(root, options(root));

      expect(titlesOf(result)).toEqual(["UNKNOWN LANGUAGE"]);
    },
    SLOW,
  );

  test(
    "check fails on Debug like build does, because both use --optimize",
    async () => {
      const root = copyFixture("minimal");
      const site = join(root, "src/Site.elm");
      writeFileSync(
        site,
        readFileSync(site, "utf8").replace(
          "{ title = post.meta.title,",
          "{ title = Debug.toString post.meta.title,",
        ),
      );

      const result = await build(root, options(root, { output: undefined }));

      expect(titlesOf(result)).toEqual(["DEBUG REMNANTS"]);
    },
    SLOW,
  );

  test(
    "serves under the base path without nesting dist in it",
    async () => {
      const root = fixturePath("base-path");
      clean(root);

      const result = await build(root, options(root));

      expect(titlesOf(result)).toEqual([]);
      expect(result.ok).toBe(true);
      const page = join(root, "dist/posts/hello-world/index.html");
      expect(readFileSync(page, "utf8")).toContain(
        'href="/blog/posts/hello-world/#top"',
      );
      expect(existsSync(join(root, "dist/blog"))).toBe(false);
    },
    SLOW,
  );

  test(
    "does not keep modules of a renamed collection folder",
    async () => {
      const root = copyFixture("minimal");
      const site = join(root, "src/Site.elm");
      writeFileSync(
        site,
        readFileSync(site, "utf8").replace(
          "import Sheaf\n",
          "import Content.Posts\nimport Sheaf\n",
        ),
      );
      // The link would fail first, once the collection it points into is gone.
      writeFileSync(
        join(root, "content/posts/2026-11-23-hello-world.md"),
        "---\ntitle: Hello, world\n---\n\nNo links.\n",
      );
      const first = await build(root, options(root, { output: undefined }));
      expect(first.ok).toBe(true);
      renameSync(join(root, "content/posts"), join(root, "content/articles"));

      const result = await build(root, options(root, { output: undefined }));

      expect(titlesOf(result)).toContain("MODULE NOT FOUND");
    },
    SLOW * 2,
  );

  test("reports an empty folder that cannot be a collection", async () => {
    const root = copyFixture("minimal");
    mkdirSync(join(root, "content/_"));

    const result = await build(root, options(root, { output: undefined }));

    expect(titlesOf(result)).toEqual(["BAD COLLECTION NAME"]);
  });

  test(
    "ignores hidden folders in content",
    async () => {
      const root = copyFixture("minimal");
      mkdirSync(join(root, "content/.obsidian"));
      writeFileSync(join(root, "content/.obsidian/notes.md"), "not a document");

      const result = await build(root, options(root, { output: undefined }));

      expect(result.ok && result.value.pages).toBe(1);
    },
    SLOW,
  );

  test(
    "highlights with the site's own grammar, again after it changes",
    async () => {
      const root = copyFixture("minimal");
      cpSync(fixturePath("highlight"), join(root, "highlight"), {
        recursive: true,
      });
      writeFileSync(
        join(root, "sheaf.json"),
        JSON.stringify({
          siteUrl: "https://example.com/",
          highlight: {
            theme: { dark: "two-colour" },
            grammars: { nginx: "highlight/toy.tmLanguage.json" },
            themes: { "two-colour": "highlight/two-colour.json" },
          },
        }),
      );
      const post = join(root, "content/posts/2026-11-23-hello-world.md");
      writeFileSync(
        post,
        `${readFileSync(post, "utf8")}\n\`\`\`nginx\nserver listen\n\`\`\`\n`,
      );
      const page = join(root, "dist/posts/hello-world/index.html");
      const orangeWord = /--shiki-dark:#ff8000[^>]*>(\w+)</i;

      const first = await build(root, options(root));
      expect(first.ok).toBe(true);
      expect(orangeWord.exec(readFileSync(page, "utf8"))?.[1]).toBe("server");

      writeFileSync(
        join(root, "highlight/toy.tmLanguage.json"),
        JSON.stringify({
          scopeName: "source.toy",
          patterns: [{ match: "\\blisten\\b", name: "keyword.control.toy" }],
        }),
      );
      const second = await build(root, options(root));
      expect(second.ok).toBe(true);
      expect(orangeWord.exec(readFileSync(page, "utf8"))?.[1]).toBe("listen");
    },
    SLOW,
  );

  test("reports a missing grammar file as a config problem", async () => {
    const root = copyFixture("minimal");
    writeFileSync(
      join(root, "sheaf.json"),
      JSON.stringify({
        siteUrl: "https://example.com/",
        highlight: { grammars: { nginx: "nginx.json" } },
      }),
    );

    const result = await build(root, options(root, { output: undefined }));

    expect(!result.ok && result.error).toEqual([
      {
        severity: "error",
        title: "BAD CONFIG",
        message:
          '"highlight.grammars.nginx" names `nginx.json`, which doesn\'t exist.',
        sourcePath: "sheaf.json",
        hint: "Paths in sheaf.json are relative to the site's folder.",
      },
    ]);
  });

  test("explains a site without sheaf.json", async () => {
    const root = copyFixture("minimal");
    rmSync(join(root, "sheaf.json"));

    const result = await build(root, options(root, { output: undefined }));

    expect(titlesOf(result)).toEqual(["NO SHEAF.JSON"]);
  });

  describe("Elm package check", () => {
    const REPO = resolve(import.meta.dir, "../..");

    test(
      "builds a copy whose source directory for Sheaf is absolute",
      async () => {
        const root = copyFixture("minimal");

        const result = await build(root, options(root));

        expect(titlesOf(result)).toEqual([]);
        expect(result.ok).toBe(true);
      },
      SLOW,
    );

    test(
      "resolves a relative source directory against the site root",
      async () => {
        const root = copyFixture("minimal");
        const path = join(root, "elm.json");
        const elm = JSON.parse(readFileSync(path, "utf8"));
        elm["source-directories"] = [
          "src",
          ".sheaf/gen",
          // The temporary folder may sit behind a symlink, as on macOS.
          relative(realpathSync(root), join(REPO, "src")),
        ];
        writeFileSync(path, JSON.stringify(elm));

        const result = await build(root, options(root));

        expect(titlesOf(result)).toEqual([]);
        expect(result.ok).toBe(true);
      },
      SLOW,
    );

    test("reports a bad elm.json before it looks at the content", async () => {
      const root = copyFixture("minimal");
      writeFileSync(join(root, "elm.json"), "{ ");
      writeFileSync(
        join(root, "content/posts/2026-11-24-bad.md"),
        "---\ntitle: [unclosed\n---\n",
      );

      const result = await build(root, options(root, { output: undefined }));

      expect(titlesOf(result)).toEqual(["BAD ELM JSON"]);
    });

    test(
      "builds a site made by init --local",
      async () => {
        const root = join(copyFixture("minimal"), "made");
        const made = await initSite(root, { local: REPO, today: "2026-01-02" });
        expect(made.ok).toBe(true);

        const result = await build(root, options(root));

        expect(titlesOf(result)).toEqual([]);
        expect(result.ok).toBe(true);
      },
      SLOW,
    );

    test("rejects a site with no Sheaf package", async () => {
      const root = copyFixture("minimal");
      const path = join(root, "elm.json");
      const elm = JSON.parse(readFileSync(path, "utf8"));
      elm["source-directories"] = ["src", ".sheaf/gen"];
      writeFileSync(path, JSON.stringify(elm));

      const result = await build(root, options(root, { output: undefined }));

      expect(titlesOf(result)).toEqual(["SHEAF PACKAGE MISSING"]);
    });

    test("reports a site without elm.json", async () => {
      const root = copyFixture("minimal");
      rmSync(join(root, "elm.json"));

      const result = await build(root, options(root, { output: undefined }));

      expect(titlesOf(result)).toEqual(["BAD ELM JSON"]);
    });
  });
});

/** Every file under `dir`, as sorted paths relative to it, with `/` separators. */
function filesUnder(dir: string): string[] {
  return readdirSync(dir, { recursive: true, withFileTypes: true })
    .filter((entry) => entry.isFile())
    .map((entry) =>
      relative(dir, join(entry.parentPath, entry.name)).split(sep).join("/"),
    )
    .sort();
}

/** The URLs of `href`, `src` and each candidate of `srcset` in `text`. */
function urlsIn(text: string): string[] {
  return [...text.matchAll(/(href|src|srcset)="([^"]*)"/g)].flatMap(
    ([, name, value = ""]) =>
      name === "srcset"
        ? value
            .split(",")
            .map((candidate) => candidate.trim().split(" ")[0] ?? "")
        : [value],
  );
}

/**
 * The URLs in `dist/` that point into the site but match no written file. A
 * full URL of the site counts as its path, because feeds make every link
 * absolute.
 */
function unresolvedLinks(root: string, siteUrl: string): string[] {
  const dist = join(root, "dist");
  const basePath = new URL(siteUrl).pathname;
  const unresolved: string[] = [];

  for (const file of filesUnder(dist)) {
    const text = readFileSync(join(dist, file), "utf8");
    for (const url of urlsIn(text)) {
      const path = url.startsWith(siteUrl)
        ? basePath + url.slice(siteUrl.length)
        : url;
      if (!path.startsWith(basePath)) continue;

      const target = join(
        dist,
        decodeURIComponent(path.slice(basePath.length).replace(/#.*$/, "")),
      );
      const resolves =
        (existsSync(target) && statSync(target).isFile()) ||
        existsSync(join(target, "index.html"));
      if (!resolves) unresolved.push(`${file}: ${url}`);
    }
  }
  return unresolved;
}

/** The files of `dist/` whose path or content mentions any of `words`. */
function filesMentioning(root: string, words: string[]): string[] {
  const dist = join(root, "dist");
  return filesUnder(dist).filter((file) => {
    const text = `${file}\n${readFileSync(join(dist, file), "utf8")}`;
    return words.some((word) => text.includes(word));
  });
}

describe("the blog fixture", () => {
  // The draft's and future post's titles, tag and URLs, so that a leak into
  // a page, a feed or the sitemap is caught.
  const hidden = [
    "secret",
    "Postcard from the future",
    "posts/plans/",
    "from-the-future",
  ];

  test(
    "writes every route, both feeds and the sitemap under the base path",
    async () => {
      const root = fixturePath("blog");
      clean(root);

      const result = await build(root, options(root));

      expect(titlesOf(result)).toEqual([]);
      const files = filesUnder(join(root, "dist"));
      expect(files).toMatchSnapshot("files");
      expect(files.filter((file) => file.endsWith(".webp"))).not.toEqual([]);
      for (const file of [
        "feed.xml",
        "atom.xml",
        "sitemap.xml",
        "index.html",
        "tags/elm/index.html",
        "posts/pictures/index.html",
        "old-post/index.html",
      ]) {
        expect(readFileSync(join(root, "dist", file), "utf8")).toMatchSnapshot(
          file,
        );
      }
      expect(unresolvedLinks(root, "https://example.com/blog/")).toEqual([]);
      expect(filesMentioning(root, hidden)).toEqual([]);
    },
    SLOW,
  );

  test(
    "builds drafts and future posts with --drafts",
    async () => {
      const root = copyFixture("blog");

      const result = await build(root, options(root, { mode: "drafts" }));

      expect(titlesOf(result)).toEqual([]);
      expect(filesMentioning(root, hidden)).toEqual(
        expect.arrayContaining([
          "feed.xml",
          "posts/from-the-future/index.html",
          "posts/plans/index.html",
          "tags/secret/index.html",
        ]),
      );
      expect(unresolvedLinks(root, "https://example.com/blog/")).toEqual([]);
    },
    SLOW,
  );

  test(
    "encodes nothing again on a second build",
    async () => {
      const root = copyFixture("blog");
      const cache = join(root, ".sheaf/cache/images");
      const cacheTimes = () =>
        filesUnder(cache).map(
          (file) => `${file} ${statSync(join(cache, file)).mtimeMs}`,
        );

      const first = await build(root, options(root));
      const firstFiles = filesUnder(join(root, "dist"));
      const firstTimes = cacheTimes();
      const second = await build(root, options(root));

      expect(first.ok && second.ok).toBe(true);
      expect(firstTimes.length).toBeGreaterThan(0);
      expect(filesUnder(join(root, "dist"))).toEqual(firstFiles);
      expect(cacheTimes()).toEqual(firstTimes);
    },
    SLOW,
  );

  test(
    "reports a misspelled component where it is used",
    async () => {
      const root = copyFixture("blog");
      const post = join(root, "content/posts/2026-11-19-pictures/index.md");
      writeFileSync(
        post,
        readFileSync(post, "utf8").replace(":::callout", ":::callot"),
      );

      const result = await build(root, options(root, { output: undefined }));

      expect(titlesOf(result)).toEqual(["UNKNOWN COMPONENT"]);
      const [diagnostic] = result.ok ? [] : result.error;
      expect(diagnostic?.sourcePath).toBe(
        "content/posts/2026-11-19-pictures/index.md",
      );
      expect(diagnostic?.span?.start.line).toBe(12);
    },
    SLOW,
  );

  test(
    "reports an attribute named __proto__ where it is used",
    async () => {
      const root = copyFixture("blog");
      const post = join(root, "content/posts/2026-11-19-pictures/index.md");
      writeFileSync(
        post,
        readFileSync(post, "utf8").replace(
          ':::callout{kind="note"}',
          ':::callout{kind="note" __proto__=a}',
        ),
      );

      const result = await build(root, options(root, { output: undefined }));

      expect(titlesOf(result)).toEqual(["UNKNOWN ATTRIBUTE"]);
      const [diagnostic] = result.ok ? [] : result.error;
      expect(diagnostic?.sourcePath).toBe(
        "content/posts/2026-11-19-pictures/index.md",
      );
      expect(diagnostic?.span?.start.line).toBe(12);
    },
    SLOW,
  );

  test(
    "publishes no file of a draft's image",
    async () => {
      const root = copyFixture("blog");
      const image = pngBytes(300, 200);
      writeFileSync(join(root, "content/posts/sketch.png"), image);
      writeFileSync(
        join(root, "content/posts/2026-11-26-sketch.md"),
        "---\ntitle: Sketch\ndraft: true\nimage: sketch.png\n---\n\n![A sketch](sketch.png)\n",
      );

      const result = await build(root, options(root));

      expect(titlesOf(result)).toEqual([]);
      const hash = imageHash(image);
      // The draft's image is still checked, so its files are in the cache.
      expect(
        filesUnder(join(root, ".sheaf/cache/images")).filter((file) =>
          file.startsWith(hash),
        ),
      ).not.toEqual([]);
      expect(filesMentioning(root, [hash])).toEqual([]);
    },
    SLOW,
  );

  test(
    "drops the cached variants of an image the site no longer uses",
    async () => {
      const root = copyFixture("blog");
      const post = join(root, "content/posts/2026-11-19-pictures");
      const photo = imageHash(readFileSync(join(post, "photo.png")));
      const cover = imageHash(readFileSync(join(post, "cover.png")));
      const cached = (hash: string) =>
        readdirSync(join(root, ".sheaf/cache/images")).filter((name) =>
          name.startsWith(hash),
        );
      expect(titlesOf(await build(root, options(root)))).toEqual([]);
      expect(cached(photo)).not.toEqual([]);

      rmSync(join(post, "photo.png"));
      writeFileSync(
        join(post, "index.md"),
        readFileSync(join(post, "index.md"), "utf8").replace(
          "![A photo](photo.png)\n",
          "",
        ),
      );
      expect(titlesOf(await build(root, options(root)))).toEqual([]);

      expect(cached(photo)).toEqual([]);
      expect(cached(cover)).not.toEqual([]);
    },
    SLOW,
  );

  test(
    "keeps a draft's cached variants through a production build",
    async () => {
      const root = copyFixture("blog");
      const image = pngBytes(300, 200);
      writeFileSync(join(root, "content/posts/sketch.png"), image);
      writeFileSync(
        join(root, "content/posts/2026-11-26-sketch.md"),
        "---\ntitle: Sketch\ndraft: true\n---\n\n![A sketch](sketch.png)\n",
      );
      const cached = () =>
        readdirSync(join(root, ".sheaf/cache/images")).filter((name) =>
          name.startsWith(imageHash(image)),
        );

      await build(root, options(root, { mode: "drafts" }));
      const before = cached();
      await build(root, options(root));

      expect(before).not.toEqual([]);
      expect(cached()).toEqual(before);
    },
    SLOW,
  );

  test(
    "reports a cache that is not a folder as an error",
    async () => {
      const root = copyFixture("blog");
      mkdirSync(join(root, ".sheaf/cache"), { recursive: true });
      writeFileSync(join(root, ".sheaf/cache/images"), "not a folder");

      const result = await build(root, options(root));

      expect(titlesOf(result)).toContain("CACHE NOT WRITABLE");
    },
    SLOW,
  );

  test.skipIf(!permissionsApply)(
    "reports an unreadable image at the image (needs file permissions)",
    async () => {
      const root = copyFixture("blog");
      const photo = join(root, "content/posts/2026-11-19-pictures/photo.png");
      chmodSync(photo, 0o000);

      try {
        const result = await build(root, options(root));

        const diagnostic = result.ok ? undefined : result.error[0];
        expect(diagnostic?.title).toBe("IMAGE NOT READABLE");
        expect(diagnostic?.sourcePath).toBe(
          "content/posts/2026-11-19-pictures/index.md",
        );
        expect(diagnostic?.span?.start.line).toBe(10);
      } finally {
        chmodSync(photo, 0o644);
      }
    },
    SLOW,
  );

  test.skipIf(!permissionsApply)(
    "warns, and still builds, when the highlight cache cannot be saved (needs file permissions)",
    async () => {
      const root = copyFixture("minimal");
      writeFileSync(
        join(root, "content/posts/2026-11-23-hello-world.md"),
        "---\ntitle: Hello, world\n---\n\n```elm\nx = 1\n```\n",
      );
      const cache = join(root, ".sheaf/cache");
      mkdirSync(cache, { recursive: true });
      chmodSync(cache, 0o555);

      try {
        const result = await build(root, options(root));

        expect(result.ok && result.value.warnings.map((w) => w.title)).toEqual([
          "CACHE NOT SAVED",
        ]);
      } finally {
        chmodSync(cache, 0o755);
      }
    },
    SLOW,
  );

  test(
    "warns, and still builds, when .sheaf/cache is a file",
    async () => {
      const root = copyFixture("minimal");
      writeFileSync(
        join(root, "content/posts/2026-11-23-hello-world.md"),
        "---\ntitle: Hello, world\n---\n\n```elm\nx = 1\n```\n",
      );
      mkdirSync(join(root, ".sheaf"), { recursive: true });
      writeFileSync(join(root, ".sheaf/cache"), "not a folder");

      const result = await build(root, options(root));

      expect(result.ok && result.value.warnings.map((w) => w.title)).toEqual([
        "CACHE NOT SAVED",
      ]);
    },
    SLOW,
  );

  test.skipIf(!permissionsApply)(
    "builds a site without images when the cache folder cannot be read (needs file permissions)",
    async () => {
      const root = copyFixture("minimal");
      const cache = join(root, ".sheaf/cache/images");
      mkdirSync(cache, { recursive: true });
      chmodSync(cache, 0o000);

      try {
        const result = await build(root, options(root));

        expect(result.ok).toBe(true);
      } finally {
        chmodSync(cache, 0o755);
      }
    },
    SLOW,
  );

  for (const name of ["archive.md", "Archive.md"]) {
    test(
      `reports a page named ${name} as a duplicate of the archive`,
      async () => {
        const root = copyFixture("blog");
        writeFileSync(
          join(root, "content/pages", name),
          "---\ntitle: Archive\n---\n\nOld posts.\n",
        );

        const result = await build(root, options(root, { output: undefined }));

        expect(titlesOf(result)).toEqual(["DUPLICATE PAGE"]);
        const message = result.ok ? "" : (result.error[0]?.message ?? "");
        expect(message).toContain("`/:slug/`");
        expect(message).toContain("`/archive/`");
      },
      SLOW,
    );
  }

  test(
    "builds the index, empty feeds and a sitemap with no posts",
    async () => {
      const root = copyFixture("blog");
      const postsDir = join(root, "content/posts");
      rmSync(postsDir, { recursive: true });
      mkdirSync(postsDir);
      writeFileSync(join(postsDir, ".gitkeep"), "");

      const result = await build(root, options(root));

      expect(titlesOf(result)).toEqual([]);
      const dist = join(root, "dist");
      expect(existsSync(join(dist, "index.html"))).toBe(true);
      expect(readFileSync(join(dist, "feed.xml"), "utf8")).not.toContain(
        "<item>",
      );
      expect(readFileSync(join(dist, "atom.xml"), "utf8")).not.toContain(
        "<entry>",
      );
      expect(readFileSync(join(dist, "sitemap.xml"), "utf8")).toContain(
        "<loc>https://example.com/blog/</loc>",
      );
    },
    SLOW,
  );
});

describe("the routes fixture", () => {
  test(
    "writes every kind of route and a feed without the blog preset",
    async () => {
      const root = fixturePath("routes");
      clean(root);

      const result = await build(root, options(root));

      expect(titlesOf(result)).toEqual([]);
      expect(filesUnder(join(root, "dist"))).toMatchSnapshot("files");
      expect(unresolvedLinks(root, "https://example.com/")).toEqual([]);
    },
    SLOW,
  );
});
