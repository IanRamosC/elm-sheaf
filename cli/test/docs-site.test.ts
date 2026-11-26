import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import {
  cpSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { build } from "../src/build";

// The first compile of a site can take several seconds.
const SLOW = 60_000;

const REPO = join(import.meta.dir, "../..");
const BASE = "/elm-sheaf";

const GUIDE = [
  ["getting-started", "Getting started"],
  ["content", "Content"],
  ["templates", "Templates"],
  ["configuration", "Configuration"],
  ["static-files-and-images", "Static files and images"],
  ["deploying", "Deploying"],
  ["cli", "CLI reference"],
] as const;

/**
 * Copies `docs/` to a temporary folder, adds `extraFiles` (paths relative to
 * the site, with their contents), and builds it. The copy reaches the Elm
 * package by an absolute path, since it no longer sits beside `src/`.
 */
async function buildDocs(extraFiles: Record<string, string> = {}) {
  const root = mkdtempSync(join(tmpdir(), "sheaf-docs-"));
  cpSync(join(REPO, "docs"), root, {
    recursive: true,
    filter: (source) => !/[\\/](\.sheaf|dist|elm-stuff)$/.test(source),
  });

  const elmJsonPath = join(root, "elm.json");
  const elmJson = JSON.parse(readFileSync(elmJsonPath, "utf8"));
  elmJson["source-directories"] = elmJson["source-directories"].map(
    (directory: string) =>
      directory === "../src" ? join(REPO, "src") : directory,
  );
  writeFileSync(elmJsonPath, JSON.stringify(elmJson, null, 2));

  for (const [path, contents] of Object.entries(extraFiles)) {
    mkdirSync(dirname(join(root, path)), { recursive: true });
    writeFileSync(join(root, path), contents);
  }

  const output = join(root, "dist");
  const result = await build(root, {
    mode: "production",
    now: new Date("2026-12-01T00:00:00Z"),
    output,
    optimize: true,
    log: () => {},
  });
  return { root, output, result };
}

function escapeHtml(text: string): string {
  return text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

describe("the documentation site", () => {
  let site: Awaited<ReturnType<typeof buildDocs>>;

  const read = (path: string) => readFileSync(join(site.output, path), "utf8");

  beforeAll(async () => {
    site = await buildDocs();
  }, SLOW);

  afterAll(() => rmSync(site.root, { recursive: true, force: true }));

  test("builds the documentation site", () => {
    expect(site.result.ok).toBe(true);
    const pages = [
      "index.html",
      "guide/index.html",
      ...GUIDE.map(([slug]) => `guide/${slug}/index.html`),
      "404.html",
      "sitemap.xml",
      "robots.txt",
    ];
    expect(
      pages.filter((page) => !existsSync(join(site.output, page))),
    ).toEqual([]);
  });

  test("lists the guide in order", () => {
    const html = read("guide/index.html");
    const positions = GUIDE.map(([, title]) => html.indexOf(`>${title}</a>`));
    expect(positions.every((position) => position >= 0)).toBe(true);
    expect(positions).toEqual([...positions].sort((a, b) => a - b));
  });

  test("links each page to its neighbours", () => {
    const content = read("guide/content/index.html");
    expect(content).toContain(`href="${BASE}/guide/getting-started/"`);
    expect(content).toContain(`href="${BASE}/guide/templates/"`);

    const first = read("guide/getting-started/index.html");
    expect(first).not.toContain("Previous");
    expect(first).toContain(`href="${BASE}/guide/content/"`);

    const last = read("guide/cli/index.html");
    expect(last).not.toContain("Next");
    expect(last).toContain(`href="${BASE}/guide/deploying/"`);
  });

  test("describes each guide page", () => {
    const index = read("guide/index.html");
    for (const [slug] of GUIDE) {
      const source = readFileSync(
        join(REPO, "docs/content/guide", `${slug}.md`),
        "utf8",
      );
      const description = /^description: (.+)$/m.exec(source)?.[1] ?? "";
      expect(description).not.toBe("");
      const escaped = escapeHtml(description);
      expect(index).toContain(escaped);
      const html = read(`guide/${slug}/index.html`);
      expect(html).toContain(`<meta name="description" content="${escaped}">`);
      expect(html).toContain(
        `<meta property="og:description" content="${escaped}">`,
      );
    }
  });

  test("the landing page links to the guide", () => {
    expect(read("index.html")).toMatch(
      new RegExp(`<a href="${BASE}/guide/"[^>]*>Read the guide</a>`),
    );
  });
});
