import { afterEach, describe, expect, test } from "bun:test";
import {
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  renameSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { join, relative } from "node:path";
import { build } from "../src/build";
import {
  copyFixture,
  fixturePath,
  removeFixtureCopies,
} from "./support/fixtures";

// The first compile of a site can take several seconds.
const SLOW = 60_000;
const now = new Date("2026-12-01T00:00:00Z");

afterEach(removeFixtureCopies);

function titlesOf(result: Awaited<ReturnType<typeof build>>): string[] {
  return result.ok ? [] : result.error.map(({ title }) => title);
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

      const result = await build(root, {
        mode: "production",
        write: true,
        now,
      });

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
    "reports every broken link and writes nothing",
    async () => {
      const root = fixturePath("broken-links");
      clean(root);

      const result = await build(root, {
        mode: "production",
        write: true,
        now,
      });

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
      const production = await build(root, {
        mode: "production",
        write: true,
        now,
      });
      expect(production.ok).toBe(true);
      expect(existsSync(join(root, "dist/posts/hello-world/index.html"))).toBe(
        true,
      );
      expect(existsSync(draftPage)).toBe(false);

      clean(root);
      const withDrafts = await build(root, {
        mode: "drafts",
        write: true,
        now,
      });
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

      const result = await build(root, {
        mode: "production",
        write: true,
        now,
      });

      expect(titlesOf(result)).toEqual(["LINK TO DRAFT"]);
    },
    SLOW,
  );

  test(
    "check compiles and renders but writes no dist",
    async () => {
      const root = fixturePath("minimal");
      clean(root);

      const result = await build(root, {
        mode: "production",
        write: false,
        now,
      });

      expect(result.ok && result.value.pages).toBe(1);
      expect(existsSync(join(root, "dist"))).toBe(false);
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

      const result = await build(root, {
        mode: "production",
        write: false,
        now,
      });

      expect(titlesOf(result)).toEqual(["DEBUG REMNANTS"]);
    },
    SLOW,
  );

  test(
    "serves under the base path without nesting dist in it",
    async () => {
      const root = fixturePath("base-path");
      clean(root);

      const result = await build(root, {
        mode: "production",
        write: true,
        now,
      });

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
      const first = await build(root, {
        mode: "production",
        write: false,
        now,
      });
      expect(first.ok).toBe(true);
      renameSync(join(root, "content/posts"), join(root, "content/articles"));

      const result = await build(root, {
        mode: "production",
        write: false,
        now,
      });

      expect(titlesOf(result)).toContain("MODULE NOT FOUND");
    },
    SLOW * 2,
  );

  test("reports an empty folder that cannot be a collection", async () => {
    const root = copyFixture("minimal");
    mkdirSync(join(root, "content/_"));

    const result = await build(root, { mode: "production", write: false, now });

    expect(titlesOf(result)).toEqual(["BAD COLLECTION NAME"]);
  });

  test(
    "ignores hidden folders in content",
    async () => {
      const root = copyFixture("minimal");
      mkdirSync(join(root, "content/.obsidian"));
      writeFileSync(join(root, "content/.obsidian/notes.md"), "not a document");

      const result = await build(root, {
        mode: "production",
        write: false,
        now,
      });

      expect(result.ok && result.value.pages).toBe(1);
    },
    SLOW,
  );

  test("explains a site without sheaf.json", async () => {
    const root = copyFixture("minimal");
    rmSync(join(root, "sheaf.json"));

    const result = await build(root, { mode: "production", write: false, now });

    expect(titlesOf(result)).toEqual(["NO SHEAF.JSON"]);
  });
});

/** Every file under `dir`, as sorted paths relative to it. */
function filesUnder(dir: string): string[] {
  return readdirSync(dir, { recursive: true, withFileTypes: true })
    .filter((entry) => entry.isFile())
    .map((entry) => relative(dir, join(entry.parentPath, entry.name)))
    .sort();
}

/**
 * The `href` and `src` values in `dist/` that point into the site but match
 * no written file. A full URL of the site counts as its path, because feeds
 * make every link absolute.
 */
function unresolvedLinks(root: string, siteUrl: string): string[] {
  const dist = join(root, "dist");
  const basePath = new URL(siteUrl).pathname;
  const unresolved: string[] = [];

  for (const file of filesUnder(dist)) {
    const text = readFileSync(join(dist, file), "utf8");
    for (const [, url] of text.matchAll(/(?:href|src)="([^"]*)"/g)) {
      const path = url?.startsWith(siteUrl)
        ? basePath + url.slice(siteUrl.length)
        : url;
      if (!path?.startsWith(basePath)) continue;

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

      const result = await build(root, {
        mode: "production",
        write: true,
        now,
      });

      expect(titlesOf(result)).toEqual([]);
      expect(filesUnder(join(root, "dist"))).toMatchSnapshot("files");
      for (const file of [
        "feed.xml",
        "atom.xml",
        "sitemap.xml",
        "index.html",
        "tags/elm/index.html",
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

      const result = await build(root, { mode: "drafts", write: true, now });

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

  for (const name of ["archive.md", "Archive.md"]) {
    test(
      `reports a page named ${name} as a duplicate of the archive`,
      async () => {
        const root = copyFixture("blog");
        writeFileSync(
          join(root, "content/pages", name),
          "---\ntitle: Archive\n---\n\nOld posts.\n",
        );

        const result = await build(root, {
          mode: "production",
          write: false,
          now,
        });

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

      const result = await build(root, {
        mode: "production",
        write: true,
        now,
      });

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

      const result = await build(root, {
        mode: "production",
        write: true,
        now,
      });

      expect(titlesOf(result)).toEqual([]);
      expect(filesUnder(join(root, "dist"))).toMatchSnapshot("files");
      expect(unresolvedLinks(root, "https://example.com/")).toEqual([]);
    },
    SLOW,
  );
});
