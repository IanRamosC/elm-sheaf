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

/** The href of the page's link with this `rel`, if it has one. */
function relHref(html: string, rel: string): string | undefined {
  const link = new RegExp(`<a [^>]*rel="${rel}"[^>]*>`).exec(html)?.[0];
  return link && /href="([^"]*)"/.exec(link)?.[1];
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
    expect(relHref(content, "prev")).toBe(`${BASE}/guide/getting-started/`);
    expect(relHref(content, "next")).toBe(`${BASE}/guide/templates/`);

    const first = read("guide/getting-started/index.html");
    expect(relHref(first, "prev")).toBeUndefined();
    expect(relHref(first, "next")).toBe(`${BASE}/guide/content/`);

    const last = read("guide/cli/index.html");
    expect(relHref(last, "prev")).toBe(`${BASE}/guide/deploying/`);
    expect(relHref(last, "next")).toBeUndefined();
  });

  test("marks the current page in the sidebar", () => {
    const html = read("guide/templates/index.html");
    const current = [...html.matchAll(/<a [^>]*aria-current="page"[^>]*>/g)];
    expect(current).toHaveLength(1);
    expect(current[0]?.[0]).toContain(`href="${BASE}/guide/templates/"`);
  });

  test(
    "shows contents on long pages only",
    async () => {
      const contents =
        /<nav [^>]*aria-label="On this page"[^>]*>(.*?)<\/nav>/s.exec(
          read("guide/templates/index.html"),
        )?.[1];
      expect(contents).toContain('href="#pages"');
      expect(contents).toContain('href="#routes"');

      const short = await buildDocs({
        "content/guide/short.md": [
          "---",
          "title: Short",
          "order: 99",
          "description: A page with a single section.",
          "---",
          "",
          "## The only section",
          "",
          "Nothing else.",
          "",
        ].join("\n"),
      });
      try {
        expect(short.result.ok).toBe(true);
        const html = readFileSync(
          join(short.output, "guide/short/index.html"),
          "utf8",
        );
        expect(html).toContain("The only section");
        expect(html).not.toContain('aria-label="On this page"');
      } finally {
        rmSync(short.root, { recursive: true, force: true });
      }
    },
    SLOW,
  );

  test("has the header links", () => {
    const html = read("index.html");
    expect(html).toMatch(new RegExp(`<a href="${BASE}/guide/"[^>]*>Guide</a>`));
    expect(html).toContain(
      '<a href="https://github.com/IanRamosC/elm-sheaf/tree/main/src/Sheaf" title="The API docs move to package.elm-lang.org with the 1.0.0 release">API</a>',
    );
    expect(html).toContain(
      '<a href="https://github.com/IanRamosC/elm-sheaf">GitHub</a>',
    );
  });

  test("shows the screenshots on the landing page", () => {
    const html = read("index.html");
    for (const scheme of ["light", "dark"]) {
      const image = new RegExp(
        `<img [^>]*src="${BASE}/images/home-${scheme}\\.png"[^>]*>`,
      ).exec(html)?.[0];
      expect(image).toMatch(/ alt="[^"]+"/);
      expect(image).toContain(`class="screenshot-${scheme}"`);
    }
    // Each scheme's stylesheet hides the other scheme's screenshot.
    const darkRules = [
      ...read("style.css").matchAll(
        /@media \(prefers-color-scheme: dark\) \{(.*?)\n\}/gs,
      ),
    ].map((match) => match[1]);
    expect(
      darkRules.some((rules) => rules?.includes(".screenshot-light")),
    ).toBe(true);
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
