import { describe, expect, test } from "bun:test";
import type { SourceDocument } from "../../src/content/document";
import type { Diagnostic } from "../../src/diagnostics/diagnostic";
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
    frontmatterPositions: [],
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

  test("makes footnote identifiers URL-safe", () => {
    const tree = parse("Text[^Ünïcode-Note].\n\n[^Ünïcode-Note]: Note.\n");
    const identifier = "%C3%BCn%C3%AFcode-note";
    expect(firstOfType(tree, "footnoteReference").identifier).toBe(identifier);
    expect(firstOfType(tree, "footnoteDefinition").identifier).toBe(identifier);
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

  test("quotes only the first line of multi-line raw HTML", () => {
    const [error] = parseErrors("<div>\n  <p>hi</p>\n</div>\n");
    expect(error?.message).toBe("This document contains raw HTML (`<div>…`).");
  });

  test("reports an inline element once, not once per tag", () => {
    const errors = parseErrors("some <b>bold</b> text");
    expect(errors.map((error) => error.title)).toEqual(["RAW HTML"]);
    expect(errors[0]?.span?.start).toEqual({ line: 1, column: 6 });
  });

  test("reports each inline element and a stray closing tag", () => {
    const errors = parseErrors("<b>a</b> <i>b</i> and </u>");
    expect(errors.map((error) => error.message)).toEqual([
      "This document contains raw HTML (`<b>`).",
      "This document contains raw HTML (`<i>`).",
      "This document contains raw HTML (`</u>`).",
    ]);
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

describe("parseMarkdown directives", () => {
  test("parses a container with its attributes in source order", () => {
    const tree = parse(':::callout{kind="warning" .wide}\nTake care.\n:::\n');
    const callout = firstOfType(tree, "containerDirective");
    expect(callout.name).toBe("callout");
    expect(callout.attributes).toEqual([
      { name: "kind", value: "warning" },
      { name: "class", value: "wide" },
    ]);
    expect(callout.children.map((child) => child.type)).toEqual(["paragraph"]);
    expect(callout.position).toEqual({
      start: { line: 1, column: 1 },
      end: { line: 3, column: 4 },
    });
  });

  test("parses a leaf, with `#x` as its id", () => {
    const tree = parse("::youtube{#intro}\n");
    expect(firstOfType(tree, "leafDirective")).toEqual({
      type: "leafDirective",
      position: { start: { line: 1, column: 1 }, end: { line: 1, column: 18 } },
      name: "youtube",
      attributes: [{ name: "id", value: "intro" }],
    });
  });

  test("keeps the order of attributes that the parser gives as an object", () => {
    const tree = parse("::x{b=1 #i a=2 open}\n");
    expect(firstOfType(tree, "leafDirective").attributes).toEqual([
      { name: "b", value: "1" },
      { name: "id", value: "i" },
      { name: "a", value: "2" },
      { name: "open", value: "" },
    ]);
  });

  // mdast-util-directive stores attributes in a plain object, where setting
  // `__proto__` to a string does nothing, so the value never reaches us.
  test("gives an attribute named __proto__ an empty value", () => {
    const tree = parse("::x{__proto__=a}\n");
    expect(firstOfType(tree, "leafDirective").attributes).toEqual([
      { name: "__proto__", value: "" },
    ]);
  });

  test("joins every class into one attribute", () => {
    const tree = parse("::x{.a .b}\n");
    expect(firstOfType(tree, "leafDirective").attributes).toEqual([
      { name: "class", value: "a b" },
    ]);
  });

  test("nests containers", () => {
    const tree = parse("::::outer\n:::inner\nText.\n:::\n::::\n");
    const outer = firstOfType(tree, "containerDirective");
    expect(outer.name).toBe("outer");
    expect(outer.children).toMatchObject([
      { type: "containerDirective", name: "inner" },
    ]);
  });

  test("reports an attribute written twice", () => {
    const errors = parseErrors("::youtube{id=a id=b}\n", 4);
    expect(errors).toEqual([
      {
        severity: "error",
        title: "DUPLICATE ATTRIBUTE",
        message: "The `id` attribute is written twice.",
        sourcePath: "content/posts/a.md",
        span: {
          start: { line: 4, column: 1 },
          end: { line: 4, column: 21 },
        },
      },
    ]);
  });

  test("counts `#x` as an id when looking for repeats", () => {
    const errors = parseErrors("::youtube{#a id=b}\n");
    expect(errors.map((error) => error.message)).toEqual([
      "The `id` attribute is written twice.",
    ]);
  });

  test("reports a container that is never closed at its opening fence", () => {
    const errors = parseErrors(
      'Before.\n\n:::callout{kind="note"}\nText.\n',
      3,
    );
    expect(errors).toEqual([
      {
        severity: "error",
        title: "UNCLOSED COMPONENT",
        message:
          "The `callout` component is never closed, so it would take in the rest of the document.",
        sourcePath: "content/posts/a.md",
        span: {
          start: { line: 5, column: 1 },
          end: { line: 5, column: 24 },
        },
        hint: "Close it with a line holding only `:::`.",
      },
    ]);
  });

  test("accepts a container closed on the last line of the file", () => {
    const tree = parse(":::callout\nText.\n:::");
    expect(firstOfType(tree, "containerDirective").name).toBe("callout");
  });

  test("reports an outer container left open after its inner one closes", () => {
    const errors = parseErrors("::::outer\n:::inner\nText.\n:::\n");
    expect(
      errors.map((error) => [error.title, error.span?.start.line]),
    ).toEqual([["UNCLOSED COMPONENT", 1]]);
  });

  for (const sample of ["12:30", "foo:bar", ":smile:", "see :ref[x]{a=1}"]) {
    test(`gives back \`${sample}\` as the text it was written as`, () => {
      const source = `At ${sample} today.`;
      const paragraph = firstOfType(parse(source), "paragraph");
      expect(paragraph.children).toEqual([
        {
          type: "text",
          position: {
            start: { line: 1, column: 1 },
            end: { line: 1, column: source.length + 1 },
          },
          value: source,
        },
      ]);
    });
  }

  test("keeps colons in heading ids and image descriptions", () => {
    const tree = parse("# Meet at 12:30\n\n![Doors open at 18:00](a.png)\n");
    expect(firstOfType(tree, "heading").id).toBe("meet-at-1230");
    expect(firstOfType(tree, "image").alt).toBe("Doors open at 18:00");
  });

  test("keeps Markdown after a colon, as if directives did not exist", () => {
    const tree = parse("see:docs[the guide](https://example.com)\n");
    expect(firstOfType(tree, "link").url).toBe("https://example.com");
  });

  test("reports a label on a leaf or a container", () => {
    const errors = parseErrors(
      "::youtube[My video]{id=abc}\n\n:::note[Title]\nText.\n:::\n",
    );
    const expected: Diagnostic = {
      severity: "error",
      title: "DIRECTIVE LABEL",
      message: "Components don't take a `[label]` in this version of Sheaf.",
      sourcePath: "content/posts/a.md",
      hint: 'Pass the text as an attribute instead, such as `::youtube{title="My video"}`.',
    };
    expect(errors).toEqual([
      {
        ...expected,
        span: { start: { line: 1, column: 1 }, end: { line: 1, column: 28 } },
      },
      {
        ...expected,
        span: { start: { line: 3, column: 1 }, end: { line: 5, column: 4 } },
      },
    ]);
  });
});
