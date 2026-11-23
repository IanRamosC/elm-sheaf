import { afterEach, describe, expect, test } from "bun:test";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { Config } from "../../src/config/config";
import { loadContent, readContentFiles } from "../../src/content/load";
import type { Diagnostic } from "../../src/diagnostics/diagnostic";

const config: Config = {
  siteUrl: new URL("https://example.com/"),
  basePath: "/",
  timezone: "UTC",
};
const buildStart = new Date("2026-11-23T12:00:00Z");

function file(path: string, frontmatter = "", body = "Body.\n") {
  const source = frontmatter ? `---\n${frontmatter}\n---\n${body}` : body;
  return { path, source };
}

function load(
  files: { path: string; source: string }[],
  mode: "production" | "drafts" = "production",
) {
  return loadContent(files, config, buildStart, mode);
}

function documents(
  files: { path: string; source: string }[],
  mode: "production" | "drafts" = "production",
) {
  const result = load(files, mode);
  if (!result.ok) throw new Error(JSON.stringify(result.error));
  return result.value;
}

function problems(files: { path: string; source: string }[]): Diagnostic[] {
  const result = load(files);
  if (result.ok) throw new Error("expected loading to fail");
  return result.error;
}

describe("loadContent documents", () => {
  test("takes slug and date from a dated file name", () => {
    const [doc] = documents([
      file("content/posts/2026-11-23-hello-world.md", "title: Hi"),
    ]);

    expect(doc).toMatchObject({
      id: "posts/hello-world",
      collection: "posts",
      sourcePath: "content/posts/2026-11-23-hello-world.md",
      slug: "hello-world",
      date: {
        instant: new Date("2026-11-23T00:00:00Z"),
        isoDate: "2026-11-23",
      },
      draft: false,
      excluded: false,
      frontmatter: { title: "Hi" },
      body: "Body.\n",
      bodyStartLine: 4,
    });
    expect(doc?.updated).toBeUndefined();
    expect(doc?.imageSource).toBeUndefined();
  });

  test("names a document folder's index.md after the folder", () => {
    const [doc] = documents([file("content/posts/typed-links/index.md")]);

    expect(doc).toMatchObject({ id: "posts/typed-links", slug: "typed-links" });
    expect(doc?.date).toBeUndefined();
  });

  test("lets frontmatter override slug and date, and removes reserved keys", () => {
    const [doc] = documents([
      file(
        "content/posts/2026-11-23-hello.md",
        [
          "slug: other",
          "date: 2026-11-01",
          "updated: 2026-11-02T10:00:00+02:00",
          "draft: false",
          "image: cover.png",
          "title: Hi",
        ].join("\n"),
      ),
    ]);

    expect(doc).toMatchObject({
      id: "posts/other",
      date: { isoDate: "2026-11-01" },
      updated: {
        instant: new Date("2026-11-02T08:00:00Z"),
        isoDate: "2026-11-02",
      },
      imageSource: "cover.png",
      frontmatter: { title: "Hi" },
    });
  });

  test("reads dates in the configured timezone", () => {
    const result = loadContent(
      [file("content/posts/2026-07-01-a.md")],
      { ...config, timezone: "Europe/Lisbon" },
      buildStart,
      "production",
    );

    expect(result.ok && result.value[0]?.date?.instant).toEqual(
      new Date("2026-06-30T23:00:00Z"),
    );
  });

  test("keeps the frontmatter positions for the host protocol", () => {
    const [doc] = documents([file("content/posts/a.md", "title: Hi")]);

    expect(doc?.frontmatterPositions.title?.key?.start).toEqual({
      line: 2,
      column: 1,
    });
  });
});

describe("loadContent exclusion", () => {
  const files = [
    file("content/posts/draft.md", "draft: true"),
    file("content/posts/future.md", "date: 2026-11-24"),
    file("content/posts/today.md", "date: 2026-11-23"),
  ];

  test("excludes drafts and future-dated documents in production", () => {
    const excluded = documents(files).map((doc) => [doc.slug, doc.excluded]);

    expect(excluded).toEqual([
      ["draft", true],
      ["future", true],
      ["today", false],
    ]);
  });

  test("includes everything when building drafts", () => {
    const docs = documents(files, "drafts");

    expect(docs.map((doc) => doc.excluded)).toEqual([false, false, false]);
    expect(docs[0]?.draft).toBe(true);
  });
});

describe("loadContent errors", () => {
  test("reports hello.md and hello/index.md as one collision naming both", () => {
    const found = problems([
      file("content/posts/hello.md"),
      file("content/posts/hello/index.md"),
    ]);

    expect(found).toHaveLength(1);
    expect(found[0]?.message).toContain("content/posts/hello.md");
    expect(found[0]?.message).toContain("content/posts/hello/index.md");
  });

  test("detects collisions on the final slug, after overrides", () => {
    const found = problems([
      file("content/posts/a.md", "slug: b"),
      file("content/posts/b.md"),
    ]);

    expect(found).toHaveLength(1);
    expect(found[0]?.message).toContain("content/posts/a.md");
    expect(found[0]?.message).toContain("content/posts/b.md");
  });

  test("allows the same slug in different collections", () => {
    expect(
      documents([file("content/posts/a.md"), file("content/notes/a.md")]),
    ).toHaveLength(2);
  });

  test("points an invalid slug override at the slug key", () => {
    for (const slug of ["../x", "a/b", '""', "a b", ".."]) {
      const [problem, ...rest] = problems([
        file("content/posts/a.md", `title: Hi\nslug: ${slug}`),
      ]);

      expect(rest).toEqual([]);
      expect(problem).toMatchObject({
        sourcePath: "content/posts/a.md",
        span: { start: { line: 3, column: 1 }, end: { line: 3, column: 5 } },
      });
    }
  });

  test("rejects a slug that is not text", () => {
    const [problem] = problems([file("content/posts/a.md", "slug: 12")]);

    expect(problem?.span?.start).toEqual({ line: 2, column: 1 });
  });

  test("names the file when its folder name is not a valid slug", () => {
    const [problem] = problems([file("content/posts/my post/index.md")]);

    expect(problem?.sourcePath).toBe("content/posts/my post/index.md");
    expect(problem?.span).toBeUndefined();
  });

  test("rejects collection names that are not lowercase words", () => {
    for (const name of ["Posts", "my_posts", "2026", "-posts"]) {
      const [problem] = problems([file(`content/${name}/a.md`)]);

      expect(problem?.title).toBe("BAD COLLECTION NAME");
      expect(problem?.message).toContain(name);
    }
  });

  test("rejects collection names that are URL schemes, and says why", () => {
    for (const name of ["data", "mailto"]) {
      const [problem] = problems([file(`content/${name}/a.md`)]);

      expect(problem?.title).toBe("BAD COLLECTION NAME");
      expect(problem?.message).toContain("URL scheme");
    }
  });

  test("reports collection folders that become the same Elm module", () => {
    const result = loadContent(
      [file("content/a-b/x.md"), file("content/a--b/y.md")],
      config,
      buildStart,
      "production",
      ["a--b", "a-b", "posts"],
    );

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toHaveLength(1);
    expect(result.error[0]).toMatchObject({
      title: "NAME CLASH",
      sourcePath: "content/a--b",
    });
    expect(result.error[0]?.message).toContain("content/a-b");
    expect(result.error[0]?.message).toContain("Content.AB");
  });

  test("reports a bad collection once however many files it holds", () => {
    const found = problems([
      file("content/Posts/a.md"),
      file("content/Posts/b.md"),
    ]);

    expect(found).toHaveLength(1);
  });

  test("rejects a file directly in content/", () => {
    const [problem] = problems([file("content/about.md")]);

    expect(problem?.sourcePath).toBe("content/about.md");
    expect(problem?.message).toContain("collection folder");
  });

  test("rejects other markdown files inside a document folder", () => {
    const [problem] = problems([file("content/posts/a/notes.md")]);

    expect(problem?.sourcePath).toBe("content/posts/a/notes.md");
  });

  test("points a wrongly typed draft at its key", () => {
    const [problem] = problems([file("content/posts/a.md", "draft: yes!")]);
    const [other] = problems([file("content/posts/a.md", 'draft: "yes"')]);

    expect(problem?.span?.start).toEqual({ line: 2, column: 1 });
    expect(other).toMatchObject({
      title: "BAD FRONTMATTER",
      span: { start: { line: 2, column: 1 }, end: { line: 2, column: 6 } },
    });
  });

  test("points a bad date at its key", () => {
    const [problem] = problems([
      file("content/posts/a.md", "date: 2026-13-01"),
    ]);

    expect(problem?.span?.start).toEqual({ line: 2, column: 1 });
  });

  test("reports a malformed date prefix in the file name", () => {
    const [problem] = problems([file("content/posts/2026-13-45-a.md")]);

    expect(problem?.sourcePath).toBe("content/posts/2026-13-45-a.md");
  });

  test("returns the errors of several files together", () => {
    const found = problems([
      file("content/posts/a.md", 'draft: "yes"'),
      file("content/posts/b.md", "slug: a/b"),
      file("content/posts/c.md", "title: [unclosed"),
      file("content/about.md"),
    ]);

    expect(found.map((problem) => problem.sourcePath)).toEqual([
      "content/posts/a.md",
      "content/posts/b.md",
      "content/posts/c.md",
      "content/about.md",
    ]);
  });
});

describe("readContentFiles", () => {
  let root: string | undefined;

  afterEach(async () => {
    if (root) await rm(root, { recursive: true });
    root = undefined;
  });

  test("reads Markdown files recursively, with / separators, sorted", async () => {
    root = await mkdtemp(join(tmpdir(), "sheaf-content-"));
    await mkdir(join(root, "content/posts/typed-links"), { recursive: true });
    await writeFile(join(root, "content/posts/b.md"), "b");
    await writeFile(join(root, "content/posts/a.md"), "a");
    await writeFile(join(root, "content/posts/typed-links/index.md"), "t");
    await writeFile(join(root, "content/posts/typed-links/cover.png"), "png");

    expect(await readContentFiles(root)).toEqual([
      { path: "content/posts/a.md", source: "a" },
      { path: "content/posts/b.md", source: "b" },
      { path: "content/posts/typed-links/index.md", source: "t" },
    ]);
  });
});
