import { describe, expect, test } from "bun:test";
import { staticClashes } from "../../src/emit/clashes";
import type { OutputFile } from "../../src/emit/write";

const outputs: OutputFile[] = [
  "index.html",
  "feed.xml",
  "posts/a/index.html",
  "_sheaf/images/h-480.webp",
].map((path) => ({ kind: "text", path, content: "" }));

function clashesOf(...paths: string[]) {
  return staticClashes(
    outputs,
    paths.map((path) => ({ kind: "copy", path, source: "/elsewhere" })),
  );
}

describe("staticClashes", () => {
  test("names the feed a static file would replace", () => {
    const [clash, ...others] = clashesOf("feed.xml");

    expect(others).toEqual([]);
    expect(clash?.title).toBe("STATIC FILE CLASH");
    expect(clash?.message).toBe(
      "static/feed.xml would replace the feed.xml that Sheaf generates.",
    );
  });

  test("compares paths ignoring case", () => {
    const diagnostics = clashesOf("Index.html");

    expect(diagnostics.map(({ message }) => message)).toEqual([
      "static/Index.html would replace the page index.html that Sheaf generates.",
    ]);
  });

  test("treats an image variant as reserved", () => {
    const [clash] = clashesOf("_sheaf/images/h-480.webp");

    expect(clash?.message).toContain("is in /_sheaf/");
  });

  test("rejects a file where an output needs a folder", () => {
    const diagnostics = clashesOf("posts/a");

    expect(diagnostics.map(({ message }) => message)).toEqual([
      "static/posts/a is a file, but page posts/a/index.html needs it to be a folder.",
    ]);
  });

  test("rejects a folder where an output is a file", () => {
    const diagnostics = clashesOf("feed.xml/x");

    expect(diagnostics.map(({ message }) => message)).toEqual([
      "static/feed.xml/x needs feed.xml to be a folder, but feed.xml is a file.",
    ]);
  });

  test("reports static files that differ only in case as one clash naming both", () => {
    const diagnostics = clashesOf("Logo.png", "logo.png");

    expect(diagnostics.map(({ message }) => message)).toEqual([
      "static/Logo.png and static/logo.png are the same file on a case-insensitive file system.",
    ]);
  });

  test("reserves /_sheaf/ for Sheaf", () => {
    const [clash] = clashesOf("_sheaf/x.txt");

    expect(clash?.hint).toBe(
      "Paths starting with `/_sheaf/` are reserved for Sheaf. Move the file elsewhere in `static/`.",
    );
  });

  test("accepts files that do not collide", () => {
    expect(clashesOf("style.css", "posts/a.png", "fonts/x.woff2")).toEqual([]);
  });
});
