import { describe, expect, test } from "bun:test";
import { HeadingIds } from "../../src/markdown/heading-id";

describe("HeadingIds", () => {
  test("lowercases, drops punctuation and hyphenates spaces", () => {
    const ids = new HeadingIds();
    expect(ids.next("Hello, World! It's 2026")).toBe("hello-world-its-2026");
  });

  test("keeps hyphens, underscores and non-ASCII letters", () => {
    const ids = new HeadingIds();
    expect(ids.next("Café_au-lait")).toBe("café_au-lait");
  });

  test("suffixes repeated headings with -1, -2", () => {
    const ids = new HeadingIds();
    expect([ids.next("Setup"), ids.next("Setup"), ids.next("Setup")]).toEqual([
      "setup",
      "setup-1",
      "setup-2",
    ]);
  });

  test("keeps every id unique when a suffixed id is also written out", () => {
    const ids = new HeadingIds();
    expect([ids.next("a"), ids.next("a"), ids.next("a 1")]).toEqual([
      "a",
      "a-1",
      "a-1-1",
    ]);
  });
});
