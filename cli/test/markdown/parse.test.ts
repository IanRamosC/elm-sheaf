import { describe, expect, test } from "bun:test";
import type { SourceDocument } from "../../src/content/document";
import { parseMarkdown } from "../../src/markdown/parse";
import type { Node } from "../../src/markdown/tree";

function documentWith(body: string, bodyStartLine = 1): SourceDocument {
  return {
    id: "posts/a",
    collection: "posts",
    sourcePath: "content/posts/a.md",
    slug: "a",
    draft: false,
    excluded: false,
    frontmatter: {},
    frontmatterPositions: {},
    body,
    bodyStartLine,
  };
}

function parse(body: string, bodyStartLine = 1): Node {
  const result = parseMarkdown(documentWith(body, bodyStartLine));
  if (!result.ok) throw new Error(JSON.stringify(result.error));
  return result.value;
}

function parseErrors(body: string, bodyStartLine = 1) {
  const result = parseMarkdown(documentWith(body, bodyStartLine));
  if (result.ok) throw new Error("expected errors");
  return result.error;
}

function typesIn(node: Node): string[] {
  const below = "children" in node ? node.children.flatMap(typesIn) : [];
  return [node.type, ...below];
}

function firstOfType<T extends Node["type"]>(
  node: Node,
  type: T,
): Extract<Node, { type: T }> {
  if (node.type === type) return node as Extract<Node, { type: T }>;
  for (const child of "children" in node ? node.children : []) {
    try {
      return firstOfType(child, type);
    } catch {}
  }
  throw new Error(`no ${type} node`);
}

describe("parseMarkdown", () => {
  test("parses a GFM table with its alignment", () => {
    const tree = parse("| a | b |\n| :- | -: |\n| 1 | 2 |\n");
    expect(typesIn(tree)).toContain("tableCell");
    expect(firstOfType(tree, "table").align).toEqual(["left", "right"]);
  });

  test("parses task list items with their checked state", () => {
    const tree = parse("- [x] done\n- [ ] todo\n- plain\n");
    const items = firstOfType(tree, "list").children.map((item) =>
      item.type === "listItem" ? item.checked : "wrong",
    );
    expect(items).toEqual([true, false, undefined]);
  });

  test("parses strikethrough", () => {
    expect(typesIn(parse("~~gone~~"))).toContain("delete");
  });

  test("parses footnotes", () => {
    const tree = parse("Text[^1].\n\n[^1]: The note.\n");
    expect(firstOfType(tree, "footnoteReference").identifier).toBe("1");
    expect(firstOfType(tree, "footnoteDefinition").identifier).toBe("1");
  });

  test("parses a literal autolink as a link", () => {
    expect(firstOfType(parse("see https://elm-lang.org now"), "link").url).toBe(
      "https://elm-lang.org",
    );
  });

  test("parses code with its language, lists, quotes, breaks and rules", () => {
    const tree = parse(
      "```elm\nx = 1\n```\n\n> quote\n\n3. a\n4. b\n\n---\n\nline  \nbreak\n\n`code` *em* **strong**\n",
    );
    expect(firstOfType(tree, "code")).toMatchObject({
      lang: "elm",
      value: "x = 1",
    });
    expect(firstOfType(tree, "list")).toMatchObject({
      ordered: true,
      start: 3,
      spread: false,
    });
    expect(typesIn(tree)).toEqual(
      expect.arrayContaining([
        "blockquote",
        "thematicBreak",
        "break",
        "inlineCode",
        "emphasis",
        "strong",
      ]),
    );
  });

  test("gives repeated headings distinct GitHub-style ids", () => {
    const tree = parse("# Setup\n\n## Setup\n\n## *Fancy* `code` here\n");
    const ids = "children" in tree ? tree.children : [];
    expect(ids.map((node) => (node.type === "heading" ? node.id : ""))).toEqual(
      ["setup", "setup-1", "fancy-code-here"],
    );
  });

  test("offsets positions by the line the body starts on", () => {
    const tree = parse("# Title\n\ntext\n", 6);
    expect(firstOfType(tree, "heading").position).toEqual({
      start: { line: 6, column: 1 },
      end: { line: 6, column: 8 },
    });
    expect(firstOfType(tree, "paragraph").position.start.line).toBe(8);
  });

  test("counts columns in UTF-16 code units, as the diagnostic renderer does", () => {
    const tree = parse("café 😀 [x](a)");
    expect(firstOfType(tree, "link").position).toEqual({
      start: { line: 1, column: 9 },
      end: { line: 1, column: 15 },
    });
  });

  test("reports a raw HTML block at its file line", () => {
    const errors = parseErrors("text\n\n<div>\n", 6);
    expect(errors).toHaveLength(1);
    expect(errors[0]).toMatchObject({
      severity: "error",
      title: "RAW HTML",
      hint: "Raw HTML is not supported. Use a component instead.",
      sourcePath: "content/posts/a.md",
      span: { start: { line: 8, column: 1 } },
    });
  });

  test("reports inline raw HTML", () => {
    const errors = parseErrors("some <b>bold</b> text");
    expect(errors.map((error) => error.title)).toEqual([
      "RAW HTML",
      "RAW HTML",
    ]);
    expect(errors[0]?.span?.start).toEqual({ line: 1, column: 6 });
  });

  test("replaces a reference-style link with a link at the reference", () => {
    const tree = parse(
      'See [text][ref] now.\n\n[ref]: https://elm-lang.org "Elm"\n',
    );
    expect(firstOfType(tree, "link")).toMatchObject({
      url: "https://elm-lang.org",
      title: "Elm",
      position: {
        start: { line: 1, column: 5 },
        end: { line: 1, column: 16 },
      },
    });
    expect(typesIn(tree)).not.toContain("definition");
    expect(typesIn(tree)).not.toContain("linkReference");
  });

  test("replaces a reference-style image with an image", () => {
    const tree = parse("![alt][pic]\n\n[pic]: /a.png\n");
    expect(firstOfType(tree, "image")).toMatchObject({
      url: "/a.png",
      alt: "alt",
    });
  });

  test("leaves a reference without a definition as plain text", () => {
    const tree = parse("[text][missing]");
    expect(typesIn(tree)).toEqual(["root", "paragraph", "text"]);
    expect(firstOfType(tree, "text").value).toBe("[text][missing]");
  });
});
