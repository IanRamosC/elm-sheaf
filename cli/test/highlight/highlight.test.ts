import { afterEach, describe, expect, test } from "bun:test";
import {
  chmodSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { SourceDocument } from "../../src/content/document";
import {
  HighlightCache,
  loadHighlightCache,
  saveHighlightCache,
} from "../../src/highlight/cache";
import {
  createCodeHighlighter,
  highlightCode,
  languagesIn,
} from "../../src/highlight/highlight";
import { parseMarkdown } from "../../src/markdown/parse";
import type { Highlight, Node } from "../../src/markdown/tree";
import { permissionsApply } from "../support/permissions";

const themes = { light: "github-light", dark: "github-dark" };

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
    aliases: [],
    body,
    bodyStartLine: 1,
  };
}

function treeOf(document: SourceDocument): Node {
  const parsed = parseMarkdown(document);
  if (!parsed.ok) throw new Error("parse failed");
  return parsed.value;
}

async function highlight(
  body: string,
  cache = new HighlightCache(),
  languages?: string[],
) {
  const document = documentOf(body);
  const tree = treeOf(document);
  using highlighter = await createCodeHighlighter(
    themes,
    languages ?? languagesIn([tree]),
    cache,
  );
  return highlightCode(tree, document, highlighter);
}

function highlightsIn(tree: Node): (Highlight | undefined)[] {
  if (tree.type === "code") return [tree.highlight];
  if (!("children" in tree)) return [];
  return tree.children.flatMap(highlightsIn);
}

async function highlightsOf(
  body: string,
  cache?: HighlightCache,
  languages?: string[],
) {
  const result = await highlight(body, cache, languages);
  if (!result.ok) throw new Error(result.error[0]?.message);
  return highlightsIn(result.value);
}

async function errorsOf(body: string) {
  const result = await highlight(body);
  if (result.ok) throw new Error("expected highlighting to fail");
  return result.error;
}

const temporaryRoots: string[] = [];

function temporarySite(): string {
  const root = mkdtempSync(join(tmpdir(), "sheaf-highlight-"));
  temporaryRoots.push(root);
  return root;
}

afterEach(() => {
  for (const root of temporaryRoots.splice(0)) {
    rmSync(root, { recursive: true, force: true });
  }
});

describe("highlightCode", () => {
  test("styles every token for both themes and keeps the source exact", async () => {
    const source = 'main = text "<&>"';
    const [highlighted] = await highlightsOf(`\`\`\`elm\n${source}\n\`\`\`\n`);

    expect(highlighted?.lines).toHaveLength(1);
    const tokens = highlighted?.lines[0] ?? [];
    expect(tokens.map(({ content }) => content).join("")).toBe(source);
    for (const { style } of tokens) {
      expect(style).toContain("color:");
      expect(style).toContain("--shiki-dark:");
    }
    expect(highlighted?.style).toContain("--shiki-dark-bg:");
  });

  test("keeps tabs and a blank last line", async () => {
    const [highlighted] = await highlightsOf("```elm\n\tx\n\n```\n");

    expect(
      highlighted?.lines.map((line) =>
        line.map(({ content }) => content).join(""),
      ),
    ).toEqual(["\tx", ""]);
  });

  test("sends an empty block as no lines", async () => {
    const [highlighted] = await highlightsOf("```elm\n```\n");

    expect(highlighted?.lines).toEqual([]);
  });

  test("highlights plain blocks without loading any grammar", async () => {
    const highlighted = await highlightsOf(
      "```\na <b>\n```\n\n```plaintext\nc & d\n```\n",
      new HighlightCache(),
      [],
    );

    expect(highlighted).toHaveLength(2);
    for (const block of highlighted) {
      expect(block?.style).toContain("--shiki-dark-bg:");
      for (const token of block?.lines.flat() ?? []) {
        expect(token.style).toBe("");
      }
    }
    expect(highlighted[0]?.lines).toEqual([[{ content: "a <b>", style: "" }]]);
  });

  test("highlights code inside other blocks", async () => {
    const highlighted = await highlightsOf(
      "- item\n\n  ```elm\n  x = 1\n  ```\n",
    );

    expect(highlighted).toHaveLength(1);
    expect(highlighted[0]?.lines).toHaveLength(1);
  });

  test("treats language names as case-sensitive", async () => {
    const [error] = await errorsOf("```Elm\nx = 1\n```\n");

    expect(error?.title).toBe("UNKNOWN LANGUAGE");
    expect(error?.hint).toContain("`elm`");
  });

  test("reports an unknown language where the block is, with a suggestion", async () => {
    const errors = await errorsOf("Intro.\n\n```elmm\nx = 1\n```\n");

    expect(errors).toEqual([
      {
        severity: "error",
        title: "UNKNOWN LANGUAGE",
        message:
          "This code block is marked as `elmm`, which Sheaf can't highlight.",
        sourcePath: "content/posts/a.md",
        span: { start: { line: 3, column: 1 }, end: { line: 5, column: 4 } },
        hint: "Did you mean `elm`? Use `text` for a block without highlighting.",
      },
    ]);
  });

  test("says why a GPL grammar is left out", async () => {
    for (const language of ["ada", "gnuplot", "nginx", "org", "racket"]) {
      const [error] = await errorsOf(`\`\`\`${language}\nx\n\`\`\`\n`);

      expect(error).toMatchObject({
        title: "UNKNOWN LANGUAGE",
        message: `This code block is marked as \`${language}\`, which Sheaf can't highlight.`,
        hint: `Shiki's ${language} grammar is GPL-3.0, so Sheaf doesn't include it. Add it to your site with "highlight.grammars" in sheaf.json.`,
      });
    }
  });

  test("never suggests a grammar it leaves out", async () => {
    for (const typo of ["nginxx", "rackett", "gnuplott"]) {
      const [error] = await errorsOf(`\`\`\`${typo}\nx\n\`\`\`\n`);

      expect(error?.hint).not.toMatch(/`(nginx|racket|gnuplot)`/);
    }
  });

  test("reports every unknown language in the document", async () => {
    const errors = await errorsOf(
      "```qqqqqq\n1\n```\n\n```elm\nx\n```\n\n```zzzzzz\n2\n```\n",
    );

    expect(errors.map(({ span }) => span?.start.line)).toEqual([1, 9]);
    expect(errors[1]?.hint).toBe(
      "Use `text` for a block without highlighting.",
    );
  });
});

describe("languagesIn", () => {
  test("lists each language once", () => {
    const tree = treeOf(
      documentOf("```elm\na\n```\n\n```\nb\n```\n\n```elm\nc\n```\n"),
    );

    expect(languagesIn([tree, tree])).toEqual(["elm"]);
  });
});

describe("the highlight cache", () => {
  const body = "```elm\nx = 1\n```\n\n```\nplain\n```\n";

  test("highlights nothing again on a second run", async () => {
    const root = temporarySite();
    const first = new HighlightCache();
    const firstRun = await highlightsOf(body, first);
    expect(first.misses).toBe(2);
    await saveHighlightCache(root, first);

    const second = await loadHighlightCache(root);
    const secondRun = await highlightsOf(body, second);

    expect(second.misses).toBe(0);
    expect(second.hits).toBe(2);
    expect(secondRun).toEqual(firstRun);
  });

  test("keeps only the entries a run used", async () => {
    const root = temporarySite();
    const first = new HighlightCache();
    await highlightsOf(body, first);
    await saveHighlightCache(root, first);

    const second = await loadHighlightCache(root);
    await highlightsOf("```elm\nx = 1\n```\n", second);
    await saveHighlightCache(root, second);

    const saved = JSON.parse(
      readFileSync(join(root, ".sheaf/cache/highlight.json"), "utf8"),
    );
    expect(Object.keys(saved)).toHaveLength(1);
  });

  for (const [description, content] of [
    ["is not valid JSON", "{ not json"],
    ["is not an object", "[]"],
  ]) {
    test(`loads as empty when highlight.json ${description}`, async () => {
      const root = temporarySite();
      mkdirSync(join(root, ".sheaf/cache"), { recursive: true });
      writeFileSync(join(root, ".sheaf/cache/highlight.json"), content ?? "");

      const cache = await loadHighlightCache(root);
      await highlightsOf(body, cache);

      expect(cache.misses).toBe(2);
    });
  }

  test("counts a malformed entry as missing", async () => {
    const root = temporarySite();
    const first = new HighlightCache();
    await highlightsOf(body, first);
    await saveHighlightCache(root, first);
    const path = join(root, ".sheaf/cache/highlight.json");
    const saved = JSON.parse(readFileSync(path, "utf8"));
    const [brokenKey = ""] = Object.keys(saved);
    saved[brokenKey] = { style: 1, lines: [] };
    writeFileSync(path, JSON.stringify(saved));

    const cache = await loadHighlightCache(root);
    await highlightsOf(body, cache);

    expect(cache.misses).toBe(1);
    expect(cache.hits).toBe(1);
  });

  test.skipIf(!permissionsApply)(
    "warns when the cache folder cannot be written (needs file permissions)",
    async () => {
      const root = temporarySite();
      const folder = join(root, ".sheaf/cache");
      mkdirSync(folder, { recursive: true });
      chmodSync(folder, 0o555);
      const cache = new HighlightCache();
      await highlightsOf(body, cache);

      try {
        const saved = await saveHighlightCache(root, cache);

        expect(!saved.ok && saved.error).toMatchObject({
          severity: "warning",
          title: "CACHE NOT SAVED",
        });
      } finally {
        chmodSync(folder, 0o755);
      }
    },
  );

  test("removes the temporary file when the rename fails", async () => {
    const root = temporarySite();
    const folder = join(root, ".sheaf/cache");
    mkdirSync(join(folder, "highlight.json"), { recursive: true });
    writeFileSync(join(folder, "highlight.json/occupied"), "");
    const cache = new HighlightCache();
    await highlightsOf(body, cache);

    const saved = await saveHighlightCache(root, cache);

    expect(!saved.ok && saved.error.title).toBe("CACHE NOT SAVED");
    expect(readdirSync(folder)).toEqual(["highlight.json"]);
  });

  test("loads as empty when there is no highlight.json", async () => {
    const cache = await loadHighlightCache(temporarySite());
    await highlightsOf(body, cache);

    expect(cache.misses).toBe(2);
  });
});
