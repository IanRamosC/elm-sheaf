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
    [],
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

  test("names a redirect by the document it redirects to", () => {
    const diagnostics = staticClashes(
      [
        {
          kind: "text",
          path: "old/index.html",
          content: "",
          aliasOf: "content/posts/new.md",
        },
      ],
      [{ kind: "copy", path: "old/index.html", source: "/elsewhere" }],
      [],
    );

    expect(diagnostics).toEqual([
      {
        severity: "error",
        title: "STATIC FILE CLASH",
        message:
          "static/old/index.html would replace the redirect old/index.html (alias of content/posts/new.md) that Sheaf generates.",
        hint: "Rename or delete the static file, or change the alias in content/posts/new.md.",
      },
    ]);
  });

  test("accepts files that do not collide", () => {
    expect(clashesOf("style.css", "posts/a.png", "fonts/x.woff2")).toEqual([]);
  });
});

describe("staticClashes with stylesheets", () => {
  const stylesheets = [{ path: "style.css", hashed: "style.3f2a9c1e.css" }];
  const files = (...paths: string[]): OutputFile[] =>
    paths.map((path) => ({ kind: "copy", path, source: "/elsewhere" }));

  test("names the hashed copy a real file would replace, once", () => {
    const diagnostics = staticClashes(
      outputs,
      files("style.css", "style.3f2a9c1e.css"),
      stylesheets,
    );

    expect(diagnostics.map(({ title, message }) => [title, message])).toEqual([
      [
        "STATIC FILE CLASH",
        "static/style.3f2a9c1e.css would replace the hashed copy of static/style.css that Sheaf generates.",
      ],
    ]);
    expect(diagnostics[0]?.hint).toContain("Rename static/style.3f2a9c1e.css");
  });

  test("skips the copy of a file that is already reported", () => {
    const diagnostics = staticClashes(outputs, files("_sheaf/x.css"), [
      { path: "_sheaf/x.css", hashed: "_sheaf/x.3f2a9c1e.css" },
    ]);

    expect(diagnostics).toHaveLength(1);
  });
});
