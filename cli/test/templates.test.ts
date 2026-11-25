import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import {
  cpSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { build } from "../src/build";

const STARTER = join(import.meta.dir, "../templates/default");
const PACKAGE_SOURCE = join(import.meta.dir, "../../src");
const SLOW = 60_000;

/**
 * Copies the starter as `sheaf init` will, until Task 8's `init` exists: the
 * welcome post gets a date and `elm.json` points at this repository's package.
 */
function copyStarter(): string {
  const root = mkdtempSync(join(tmpdir(), "sheaf-starter-"));
  cpSync(STARTER, root, { recursive: true });

  const welcome = join(root, "content/posts/welcome.md");
  writeFileSync(
    welcome,
    readFileSync(welcome, "utf8").replaceAll("{{today}}", "2026-01-02"),
  );
  writeFileSync(
    join(root, "elm.json"),
    JSON.stringify({
      type: "application",
      "source-directories": ["src", ".sheaf/gen", PACKAGE_SOURCE],
      "elm-version": "0.19.3",
      dependencies: {
        direct: {
          "elm/core": "1.0.5",
          "elm/json": "1.1.4",
          "elm/time": "1.0.0",
        },
        indirect: {},
      },
      "test-dependencies": { direct: {}, indirect: {} },
    }),
  );
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
    root = copyStarter();
    built = await build(root, {
      mode: "production",
      now: new Date("2026-01-03T00:00:00Z"),
      output: join(root, "dist"),
      optimize: true,
      log: () => {},
    });
  }, SLOW);

  afterAll(() => rmSync(root, { recursive: true, force: true }));

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
