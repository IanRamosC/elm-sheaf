import { describe, expect, test } from "bun:test";
import type { Diagnostic } from "../../src/diagnostics/diagnostic";
import { renderDiagnostic } from "../../src/diagnostics/render";
import { collect, err, ok } from "../../src/result";

const sourceLine =
  "As covered in [the first post](posts:helo-world), the typed links catch typos.";

const brokenLink: Diagnostic = {
  severity: "error",
  title: "BROKEN LINK",
  message:
    "This post links to `posts:helo-world`, but no document has that slug.",
  sourcePath: "content/posts/a.md",
  span: { start: { line: 9, column: 32 }, end: { line: 9, column: 48 } },
  hint: "Did you mean `posts:hello-world`?",
};

const source = `${Array.from({ length: 8 }, (_, i) => `line ${i + 1}`).join("\n")}\n${sourceLine}\n`;

describe("renderDiagnostic", () => {
  test("renders header, message, source line, carets and hint", () => {
    const lines = renderDiagnostic(brokenLink, source).split("\n");

    const header = lines[0] ?? "";
    expect(header).toHaveLength(80);
    expect(header.startsWith("-- BROKEN LINK -")).toBe(true);
    expect(header.endsWith("- content/posts/a.md:9:32")).toBe(true);
    expect(lines.slice(1)).toEqual([
      "",
      brokenLink.message,
      "",
      `    9| ${sourceLine}`,
      `${" ".repeat(7 + 31)}${"^".repeat(16)}`,
      "",
      "Did you mean `posts:hello-world`?",
    ]);
  });

  test("renders only header and message without a span", () => {
    const { span: _span, hint: _hint, ...withoutSpan } = brokenLink;
    const lines = renderDiagnostic(withoutSpan, source).split("\n");

    expect(lines).toHaveLength(3);
    expect(lines[0]).toHaveLength(80);
    expect(lines[0]?.endsWith(" content/posts/a.md")).toBe(true);
    expect(lines.slice(1)).toEqual(["", brokenLink.message]);
  });

  test("excerpts a multi-line span from a CRLF source without a stray CR", () => {
    const crlfSource = "title: a\r\ntags: [elm,\r\n  42]\r\n";
    const span = { start: { line: 2, column: 7 }, end: { line: 3, column: 6 } };
    const { hint: _hint, ...withoutHint } = brokenLink;
    const lines = renderDiagnostic({ ...withoutHint, span }, crlfSource).split(
      "\n",
    );

    expect(lines.slice(4)).toEqual([
      "    2| tags: [elm,",
      `${" ".repeat(7 + 6)}${"^".repeat(5)}`,
    ]);
  });

  test("keeps four dashes before a path too long for 80 columns", () => {
    const sourcePath = `content/${"deeply/".repeat(12)}a.md`;
    const header =
      renderDiagnostic({ ...brokenLink, sourcePath }, source).split("\n")[0] ??
      "";

    expect(header).toBe(`-- BROKEN LINK ---- ${sourcePath}:9:32`);
    expect(header.length).toBeGreaterThan(80);
  });
});

describe("collect", () => {
  test("gathers every error in order", () => {
    expect(collect([ok(1), err(["a"]), err(["b", "c"])])).toEqual(
      err(["a", "b", "c"]),
    );
  });

  test("returns all values when nothing failed", () => {
    expect(collect([ok(1), ok(2)])).toEqual(ok([1, 2]));
  });
});
