import { describe, expect, test } from "bun:test";
import type { SourceDocument } from "../../src/content/document";
import { foldOf, slugOf, slugTable } from "../../src/content/slug";

function documentWith(frontmatter: Record<string, unknown>): SourceDocument {
  return {
    id: "posts/a",
    collection: "posts",
    sourcePath: "content/posts/a.md",
    slug: "a",
    draft: false,
    excluded: false,
    frontmatter,
    frontmatterPositions: {},
    body: "",
    bodyStartLine: 1,
  };
}

describe("slugOf", () => {
  test("lowercases and strips Latin accents", () => {
    expect(slugOf("Elm")).toBe("elm");
    expect(slugOf("Élm")).toBe("elm");
    expect(slugOf("Tiếng Việt")).toBe("tieng-viet");
  });

  test("turns runs of punctuation and space into one separator", () => {
    expect(slugOf("C++")).toBe("c");
    expect(slugOf("  Web  Dev! ")).toBe("web-dev");
    expect(slugOf("+++")).toBe("");
  });

  test("applies NFKD compatibility mappings", () => {
    expect(slugOf("ﬁle")).toBe("file");
  });

  test("keeps non-Latin scripts intact", () => {
    expect(slugOf("日本")).toBe("日本");
    expect(slugOf("がっこう")).toBe("がっこう");
    expect(slugOf("हिन्दी")).toBe("हिन्दी");
    expect(slugOf("한국")).toBe("한국".normalize("NFC"));
    expect(slugOf("ばか")).not.toBe(slugOf("はか"));
  });

  test("folds case beyond lowercasing", () => {
    expect(slugOf("ΟΔΟΣ")).toBe(slugOf("οδος"));
    expect(slugOf("straße")).toBe("strasse");
    expect(slugOf("STRASSE")).toBe("strasse");
  });
});

describe("foldOf", () => {
  test("keeps punctuation that distinguishes spellings", () => {
    expect(foldOf("C++")).toBe("c++");
  });

  test("folds case, accents and separators", () => {
    expect(foldOf("Élm")).toBe(foldOf("elm"));
    expect(foldOf("Web  Dev")).toBe(foldOf("Web Dev"));
    expect(foldOf("open source")).toBe(foldOf("open-source"));
    expect(foldOf("open_source")).toBe(foldOf("open-source"));
    expect(foldOf("-x_")).toBe("x");
  });
});

describe("slugTable", () => {
  test("lists every distinct string in first-seen order", () => {
    const table = slugTable([
      documentWith({
        tags: ["Elm", "elm", "hasOwnProperty", "__proto__"],
        series: { name: "Intro" },
        order: 3,
        featured: true,
      }),
      documentWith({ tags: ["Elm"] }),
    ]);
    expect(table.map((entry) => entry.value)).toEqual([
      "Elm",
      "elm",
      "hasOwnProperty",
      "__proto__",
      "Intro",
    ]);
    expect(table[0]).toEqual({ value: "Elm", slug: "elm", folded: "elm" });
  });
});
