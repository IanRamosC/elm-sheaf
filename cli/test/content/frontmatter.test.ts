import { describe, expect, test } from "bun:test";
import { splitFrontmatter } from "../../src/content/frontmatter";

const sourcePath = "content/posts/a.md";

const post = `---
title: Hello
tags: [elm, 42]
author:
  name: Ian
---
Body text.
`;

function span(
  startLine: number,
  startColumn: number,
  endLine: number,
  endColumn: number,
) {
  return {
    start: { line: startLine, column: startColumn },
    end: { line: endLine, column: endColumn },
  };
}

function split(source: string) {
  const result = splitFrontmatter(source, sourcePath);
  if (!result.ok) throw new Error(JSON.stringify(result.error));
  return result.value;
}

function problems(source: string) {
  const result = splitFrontmatter(source, sourcePath);
  if (result.ok) throw new Error("expected frontmatter to be rejected");
  return result.error;
}

describe("splitFrontmatter", () => {
  test("reads data, body and the line the body starts on", () => {
    const { data, body, bodyStartLine } = split(post);

    expect(data).toEqual({
      title: "Hello",
      tags: ["elm", 42],
      author: { name: "Ian" },
    });
    expect(body).toBe("Body text.\n");
    expect(bodyStartLine).toBe(7);
  });

  test("locates keys and values in file lines and columns", () => {
    const { positions } = split(post);

    expect(positions[""]).toEqual({ value: span(1, 1, 1, 4) });
    expect(positions.tags).toEqual({
      key: span(3, 1, 3, 5),
      value: span(3, 7, 3, 16),
    });
    expect(positions["tags.1"]).toEqual({ value: span(3, 13, 3, 15) });
    expect(positions["author.name"]).toEqual({
      key: span(5, 3, 5, 7),
      value: span(5, 9, 5, 12),
    });
  });

  test("treats a file without frontmatter as all body", () => {
    const result = split("Just text.\n");

    expect(result.data).toEqual({});
    expect(result.body).toBe("Just text.\n");
    expect(result.bodyStartLine).toBe(1);
    expect(result.positions[""]).toEqual({ value: span(1, 1, 1, 1) });
  });

  test("accepts empty frontmatter", () => {
    const result = split("---\n---\nBody\n");

    expect(result.data).toEqual({});
    expect(result.body).toBe("Body\n");
    expect(result.bodyStartLine).toBe(3);
  });

  test("gives CRLF and BOM input the same positions as LF", () => {
    const expected = split(post);
    for (const variant of [
      post.replaceAll("\n", "\r\n"),
      `﻿${post}`,
      `﻿${post.replaceAll("\n", "\r\n")}`,
    ]) {
      const result = split(variant);
      expect(result.data).toEqual(expected.data);
      expect(result.positions).toEqual(expected.positions);
      expect(result.bodyStartLine).toBe(expected.bodyStartLine);
    }
  });

  test("rejects an opening fence with no closing fence", () => {
    const [problem, ...rest] = problems("---\ntitle: Hello\n\nBody\n");

    expect(rest).toEqual([]);
    expect(problem).toMatchObject({
      severity: "error",
      title: "BAD FRONTMATTER",
      sourcePath,
      span: span(1, 1, 1, 4),
    });
  });

  test("locates a YAML syntax error in the file", () => {
    const [problem] = problems("---\ntitle: ok\ntags: [a, b\nother: 1\n---\n");

    expect(problem?.title).toBe("BAD FRONTMATTER");
    expect(problem?.span?.start.line).toBeGreaterThanOrEqual(3);
    expect(problem?.span?.start.line).toBeLessThanOrEqual(5);
  });

  test("rejects frontmatter that is not a mapping", () => {
    const [problem] = problems("---\n- a\n- b\n---\n");

    expect(problem).toMatchObject({
      title: "BAD FRONTMATTER",
      span: { start: { line: 2, column: 1 } },
    });
  });
});
