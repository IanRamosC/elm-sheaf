import { afterEach, describe, expect, test } from "bun:test";
import {
  existsSync,
  readFileSync,
  renameSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { join } from "node:path";
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
    },
    SLOW,
  );

  test(
    "renders a draft only in drafts mode",
    async () => {
      const root = fixturePath("drafts");
      const draftPage = join(root, "dist/posts/work-in-progress/index.html");

      clean(root);
      await build(root, { mode: "production", write: true, now });
      expect(existsSync(draftPage)).toBe(false);

      clean(root);
      await build(root, { mode: "drafts", write: true, now });
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

  test("explains a site without sheaf.json", async () => {
    const root = copyFixture("minimal");
    rmSync(join(root, "sheaf.json"));

    const result = await build(root, { mode: "production", write: false, now });

    expect(titlesOf(result)).toEqual(["NO SHEAF.JSON"]);
  });
});
