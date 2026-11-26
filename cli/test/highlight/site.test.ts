import { afterEach, describe, expect, test } from "bun:test";
import { cpSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { Config } from "../../src/config/config";
import type { SourceDocument } from "../../src/content/document";
import { HighlightCache } from "../../src/highlight/cache";
import {
  createCodeHighlighter,
  highlightCode,
  languagesIn,
} from "../../src/highlight/highlight";
import { loadSiteHighlight } from "../../src/highlight/site";
import { parseMarkdown } from "../../src/markdown/parse";
import type { Highlight, Node } from "../../src/markdown/tree";
import { fixturePath } from "../support/fixtures";

const ORANGE = /#ff8000/i;

const roots: string[] = [];

afterEach(() => {
  for (const root of roots.splice(0)) {
    rmSync(root, { recursive: true, force: true });
  }
});

/** A site folder holding the toy grammar and the two-colour theme under `highlight/`. */
function siteWithFiles(): string {
  const root = mkdtempSync(join(tmpdir(), "sheaf-site-highlight-"));
  roots.push(root);
  cpSync(fixturePath("highlight"), join(root, "highlight"), {
    recursive: true,
  });
  return root;
}

function highlightConfig(
  grammars: Record<string, string>,
  themes: Record<string, string> = {},
  theme = { light: "github-light", dark: "github-dark" },
): Config["highlight"] {
  return {
    theme,
    grammars: new Map(Object.entries(grammars)),
    themes: new Map(Object.entries(themes)),
  };
}

function documentOf(body: string): SourceDocument {
  return {
    id: "posts/a",
    collection: "posts",
    sourcePath: "content/posts/a.md",
    slug: "a",
    draft: false,
    excluded: false,
    frontmatter: {},
    frontmatterPositions: [],
    body,
    bodyStartLine: 1,
  };
}

function highlightsIn(tree: Node): (Highlight | undefined)[] {
  if (tree.type === "code") return [tree.highlight];
  if (!("children" in tree)) return [];
  return tree.children.flatMap(highlightsIn);
}

async function highlightWith(
  root: string,
  config: Config["highlight"],
  body: string,
  cache = new HighlightCache(),
): Promise<Highlight | undefined> {
  const site = await loadSiteHighlight(root, config);
  if (!site.ok) throw new Error(site.error[0]?.message);
  const document = documentOf(body);
  const tree = parseMarkdown(document);
  if (!tree.ok) throw new Error("parse failed");
  using highlighter = await createCodeHighlighter(
    config.theme,
    languagesIn([tree.value]),
    cache,
    site.value,
  );
  const highlighted = highlightCode(tree.value, document, highlighter);
  if (!highlighted.ok) throw new Error(highlighted.error[0]?.hint);
  return highlightsIn(highlighted.value)[0];
}

async function errorsOf(root: string, config: Config["highlight"]) {
  const site = await loadSiteHighlight(root, config);
  if (site.ok) throw new Error("expected the files to be rejected");
  return site.error;
}

describe("a site's own grammars and themes", () => {
  test("highlight a language under the name of a grammar Sheaf leaves out", async () => {
    const root = siteWithFiles();
    const highlighted = await highlightWith(
      root,
      highlightConfig({ nginx: "highlight/toy.tmLanguage.json" }),
      "```nginx\nserver here\n```\n",
    );

    const [keyword] = highlighted?.lines[0] ?? [];
    expect(keyword).toMatchObject({ content: "server" });
    expect(keyword?.style).toMatch(/color:#D73A49/i);
  });

  test("replace a grammar Shiki has", async () => {
    const root = siteWithFiles();
    const highlighted = await highlightWith(
      root,
      highlightConfig({ elm: "highlight/toy.tmLanguage.json" }),
      "```elm\nserver = 1\n```\n",
    );

    expect(highlighted?.lines[0]?.map(({ content }) => content)).toEqual([
      "server",
      " = 1",
    ]);
  });

  test("take over every name of the grammar they replace", async () => {
    const root = siteWithFiles();
    const highlighted = await highlightWith(
      root,
      highlightConfig({ javascript: "highlight/toy.tmLanguage.json" }),
      "```js\nserver = 1\n```\n",
    );

    const [keyword] = highlighted?.lines[0] ?? [];
    expect(keyword).toMatchObject({ content: "server" });
    expect(keyword?.style).toMatch(/color:#D73A49/i);
  });

  test("replace a grammar that another one embeds", async () => {
    const root = siteWithFiles();
    const config = highlightConfig({
      javascript: "highlight/toy.tmLanguage.json",
    });
    const body =
      "```js\nserver = 1\n```\n\n```html\n<script>server</script>\n```\n";
    const site = await loadSiteHighlight(root, config);
    if (!site.ok) throw new Error(site.error[0]?.message);
    const document = documentOf(body);
    const tree = parseMarkdown(document);
    if (!tree.ok) throw new Error("parse failed");
    using highlighter = await createCodeHighlighter(
      config.theme,
      languagesIn([tree.value]),
      new HighlightCache(),
      site.value,
    );
    const highlighted = highlightCode(tree.value, document, highlighter);
    if (!highlighted.ok) throw new Error(highlighted.error[0]?.hint);
    const [js, html] = highlightsIn(highlighted.value);

    expect(js?.lines[0]?.map(({ content }) => content)).toEqual([
      "server",
      " = 1",
    ]);
    expect(js?.lines[0]?.[0]?.style).toMatch(/color:#D73A49/i);
    expect(html?.lines[0]?.map(({ content }) => content).join("")).toBe(
      "<script>server</script>",
    );
  });

  test("give a theme that highlight.theme can name", async () => {
    const root = siteWithFiles();
    const highlighted = await highlightWith(
      root,
      highlightConfig(
        { nginx: "highlight/toy.tmLanguage.json" },
        { "two-colour": "highlight/two-colour.json" },
        { light: "github-light", dark: "two-colour" },
      ),
      "```nginx\nserver\n```\n",
    );

    expect(highlighted?.style).toContain("--shiki-dark-bg:#101010");
    expect(highlighted?.lines[0]?.[0]?.style).toMatch(ORANGE);
  });

  test("highlight again when a file changes", async () => {
    const root = siteWithFiles();
    const config = highlightConfig(
      { nginx: "highlight/toy.tmLanguage.json" },
      { "two-colour": "highlight/two-colour.json" },
      { light: "github-light", dark: "two-colour" },
    );
    const cache = new HighlightCache();
    const body = "```nginx\nserver listen\n```\n";
    const before = await highlightWith(root, config, body, cache);
    writeFileSync(
      join(root, "highlight/toy.tmLanguage.json"),
      JSON.stringify({
        scopeName: "source.toy",
        patterns: [{ match: "\\blisten\\b", name: "keyword.control.toy" }],
      }),
    );

    const after = await highlightWith(root, config, body, cache);

    expect(cache.misses).toBe(2);
    expect(after).not.toEqual(before);
    expect(after?.lines[0]?.map(({ content }) => content)).toEqual([
      "server ",
      "listen",
    ]);
  });

  test("report every file that can't be used, with its key", async () => {
    const root = siteWithFiles();
    writeFileSync(join(root, "highlight/broken.json"), "{ not json");
    writeFileSync(join(root, "highlight/list.json"), "[]");
    writeFileSync(
      join(root, "highlight/no-patterns.json"),
      '{"scopeName":"source.x"}',
    );
    writeFileSync(join(root, "highlight/no-colours.json"), '{"name":"x"}');
    mkdirSync(join(root, "highlight/folder.json"));

    const errors = await errorsOf(
      root,
      highlightConfig(
        {
          missing: "highlight/missing.json",
          folder: "highlight/folder.json",
          broken: "highlight/broken.json",
          list: "highlight/list.json",
          half: "highlight/no-patterns.json",
        },
        { plain: "highlight/no-colours.json" },
      ),
    );

    expect(errors.map(({ title }) => title)).toEqual(
      Array(6).fill("BAD CONFIG"),
    );
    expect(errors.every(({ sourcePath }) => sourcePath === "sheaf.json")).toBe(
      true,
    );
    expect(errors.map(({ message }) => message)).toEqual([
      '"highlight.grammars.missing" names `highlight/missing.json`, which doesn\'t exist.',
      expect.stringContaining(
        '"highlight.grammars.folder" names `highlight/folder.json`, which can\'t be read',
      ),
      expect.stringContaining(
        '"highlight.grammars.broken" names `highlight/broken.json`, which isn\'t valid JSON:',
      ),
      '"highlight.grammars.list" names `highlight/list.json`, which isn\'t a TextMate grammar: it needs "scopeName" and "patterns".',
      '"highlight.grammars.half" names `highlight/no-patterns.json`, which isn\'t a TextMate grammar: it needs "scopeName" and "patterns".',
      '"highlight.themes.plain" names `highlight/no-colours.json`, which isn\'t a VS Code theme: it needs "tokenColors" or "colors".',
    ]);
  });
});
