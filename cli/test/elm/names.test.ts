import { describe, expect, test } from "bun:test";
import type { SourceDocument } from "../../src/content/document";
import {
  assignValueNames,
  elmModuleName,
  elmValueName,
} from "../../src/elm/names";

function documentAt(
  collection: string,
  slug: string,
  sourcePath = `content/${collection}/${slug}.md`,
): SourceDocument {
  return {
    id: `${collection}/${slug}`,
    collection,
    sourcePath,
    slug,
    draft: false,
    excluded: false,
    frontmatter: {},
    frontmatterPositions: {},
    body: "",
    bodyStartLine: 1,
  };
}

describe("elmModuleName", () => {
  test("capitalises each part", () => {
    expect(elmModuleName("release-notes")).toEqual({
      ok: true,
      value: "ReleaseNotes",
    });
    expect(elmModuleName("posts")).toEqual({ ok: true, value: "Posts" });
  });

  test("fails when nothing usable is left", () => {
    expect(elmModuleName("日本").ok).toBe(false);
  });
});

describe("elmValueName", () => {
  test("lowercases the first part and capitalises the rest", () => {
    expect(elmValueName("hello-world")).toEqual({
      ok: true,
      value: "helloWorld",
    });
    expect(elmValueName("hello_world")).toEqual({
      ok: true,
      value: "helloWorld",
    });
  });

  test("prefixes a leading digit with n", () => {
    expect(elmValueName("2026-recap")).toEqual({
      ok: true,
      value: "n2026Recap",
    });
  });

  test("suffixes Elm keywords with an underscore", () => {
    expect(elmValueName("type")).toEqual({ ok: true, value: "type_" });
    expect(elmValueName("alias")).toEqual({ ok: true, value: "alias_" });
  });

  test("folds accents to their base letters", () => {
    expect(elmValueName("café-notes")).toEqual({
      ok: true,
      value: "cafeNotes",
    });
  });

  test("fails when no letters or digits survive", () => {
    expect(elmValueName("日本").ok).toBe(false);
    expect(elmValueName("---").ok).toBe(false);
  });
});

describe("assignValueNames", () => {
  test("maps each document id to its value name", () => {
    const result = assignValueNames([
      documentAt("posts", "hello-world"),
      documentAt("pages", "hello-world"),
    ]);
    expect(result.ok && [...result.value]).toEqual([
      ["posts/hello-world", "helloWorld"],
      ["pages/hello-world", "helloWorld"],
    ]);
  });

  test("reports a clash once, naming every file involved", () => {
    const result = assignValueNames([
      documentAt("posts", "hello-world", "content/posts/hello-world.md"),
      documentAt("posts", "hello_world", "content/posts/hello_world.md"),
    ]);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toHaveLength(1);
    const [diagnostic] = result.error;
    expect(diagnostic?.severity).toBe("error");
    expect(diagnostic?.message).toContain("content/posts/hello-world.md");
    expect(diagnostic?.message).toContain("content/posts/hello_world.md");
    expect(diagnostic?.message).toContain("helloWorld");
  });

  test("reports an unusable slug against its file, with other errors", () => {
    const result = assignValueNames([
      documentAt("posts", "日本", "content/posts/日本.md"),
      documentAt("posts", "a-b", "content/posts/a-b.md"),
      documentAt("posts", "a_b", "content/posts/a_b.md"),
    ]);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toHaveLength(2);
    expect(result.error.map((d) => d.sourcePath)).toContain(
      "content/posts/日本.md",
    );
  });
});
