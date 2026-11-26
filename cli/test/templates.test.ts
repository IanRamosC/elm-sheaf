import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import {
  existsSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  rmSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { build } from "../src/build";
import { initSite } from "../src/init/init";

const STARTER = join(import.meta.dir, "../templates/default");
const REPO = join(import.meta.dir, "../..");
const SLOW = 60_000;

/** Creates the site the way `sheaf init --local` does, in a folder of its own. */
async function initStarter(): Promise<string> {
  const root = join(mkdtempSync(join(tmpdir(), "sheaf-starter-")), "site");
  const created = await initSite(root, { local: REPO, today: "2026-01-02" });
  if (!created.ok) throw new Error(created.error[0]?.message);
  return root;
}

function htmlFilesIn(directory: string): string[] {
  return readdirSync(directory, { recursive: true, encoding: "utf8" })
    .filter((path) => path.endsWith(".html"))
    .map((path) => join(directory, path));
}

describe("the default starter", () => {
  let root = "";
  let built: Awaited<ReturnType<typeof build>>;
  const read = (path: string) => readFileSync(join(root, "dist", path), "utf8");

  beforeAll(async () => {
    root = await initStarter();
    built = await build(root, {
      mode: "production",
      now: new Date("2026-01-03T00:00:00Z"),
      output: join(root, "dist"),
      optimize: true,
      log: () => {},
    });
  }, SLOW);

  afterAll(() => rmSync(dirname(root), { recursive: true, force: true }));

  test("builds", () => {
    expect(built.ok ? [] : built.error.map(({ title }) => title)).toEqual([]);
  });

  test("every page has a skip link to its main landmark", () => {
    for (const path of ["index.html", "about/index.html", "404.html"]) {
      const page = read(path);
      expect(page).toContain('href="#main"');
      expect(page).toContain('<main id="main">');
    }
  });

  test("every page links the favicon, which is written to the site", () => {
    expect(read("index.html")).toContain(
      '<link rel="icon" href="/favicon.svg" type="image/svg+xml">',
    );
    expect(existsSync(join(root, "dist", "favicon.svg"))).toBe(true);
  });

  test("the welcome post has highlighted code and a callout", () => {
    const post = read("posts/welcome/index.html");
    expect(post).toContain('<pre class="shiki"');
    expect(post).toContain('<aside class="callout note">');
    expect(post).toContain('property="og:type" content="article"');
  });

  test("each feed is linked once from the head", () => {
    const index = read("index.html");
    expect(
      index.split('rel="alternate" type="application/rss+xml"'),
    ).toHaveLength(2);
    expect(
      index.split('rel="alternate" type="application/atom+xml"'),
    ).toHaveLength(2);
  });

  test("the feed has the welcome post", () => {
    expect(read("feed.xml")).toContain("/posts/welcome/");
  });

  test("the output has no JavaScript", () => {
    for (const path of htmlFilesIn(join(root, "dist"))) {
      expect(readFileSync(path, "utf8")).not.toContain("<script");
    }
  });

  test("the Elm is formatted with elm-format", () => {
    const result = spawnSync(
      "elm-format",
      ["--validate", join(STARTER, "src")],
      {
        encoding: "utf8",
      },
    );
    expect((result.stdout + result.stderr).trim()).toBe("[]");
    expect(result.status).toBe(0);
  });

  test("the deploy workflow keeps hidden files such as .well-known", () => {
    const workflow = readFileSync(
      join(STARTER, ".github/workflows/deploy.yml"),
      "utf8",
    );
    expect(workflow).toContain("include-hidden-files: true");
  });
});
