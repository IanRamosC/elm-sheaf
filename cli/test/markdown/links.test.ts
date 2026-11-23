import { describe, expect, test } from "bun:test";
import type { SourceDocument } from "../../src/content/document";
import { checkLinks } from "../../src/markdown/links";
import { parseMarkdown } from "../../src/markdown/parse";
import type { Node } from "../../src/markdown/tree";

function documentAt(
  collection: string,
  slug: string,
  body = "",
): SourceDocument {
  return {
    id: `${collection}/${slug}`,
    collection,
    sourcePath: `content/${collection}/${slug}.md`,
    slug,
    draft: false,
    excluded: false,
    frontmatter: {},
    frontmatterPositions: {},
    body,
    bodyStartLine: 1,
  };
}

const all = [
  documentAt("posts", "a"),
  documentAt("posts", "hello-world"),
  documentAt("posts", "café-notes"),
  documentAt("pages", "about"),
];

function check(body: string) {
  const document = documentAt("posts", "a", body);
  const parsed = parseMarkdown(document);
  if (!parsed.ok) throw new Error("parse failed");
  return checkLinks(parsed.value, document, all);
}

function linkIn(body: string): Node {
  const result = check(body);
  if (!result.ok) throw new Error(JSON.stringify(result.error));
  const paragraph = result.value.type === "root" && result.value.children[0];
  if (!paragraph || !("children" in paragraph)) throw new Error("no paragraph");
  const link = paragraph.children[0];
  if (!link) throw new Error("no link");
  return link;
}

function errorsFor(body: string) {
  const result = check(body);
  if (result.ok) throw new Error("expected errors");
  return result.error;
}

describe("checkLinks", () => {
  test("turns a collection link into a sheafLink", () => {
    expect(linkIn("[x](posts:hello-world)")).toMatchObject({
      type: "sheafLink",
      collection: "posts",
      slug: "hello-world",
    });
  });

  test("keeps the fragment of a collection link", () => {
    expect(linkIn("[x](posts:hello-world#setup)")).toMatchObject({
      type: "sheafLink",
      slug: "hello-world",
      fragment: "setup",
    });
  });

  test("keeps the title and the link text", () => {
    const link = linkIn('[the *post*](posts:a "Title")');
    expect(link).toMatchObject({ type: "sheafLink", title: "Title" });
    expect("children" in link && link.children.map((c) => c.type)).toEqual([
      "text",
      "emphasis",
    ]);
  });

  test("reports a mistyped slug with suggestions at the link", () => {
    const errors = errorsFor("[the first post](posts:helo-world)");
    expect(errors).toHaveLength(1);
    expect(errors[0]).toEqual({
      severity: "error",
      title: "BROKEN LINK",
      message:
        "This document links to `posts:helo-world`, but no document in `posts` has that slug.",
      sourcePath: "content/posts/a.md",
      span: { start: { line: 1, column: 1 }, end: { line: 1, column: 35 } },
      hint: "Did you mean one of these?\n\n    posts:hello-world",
    });
  });

  test("lists the known collections for an unknown collection", () => {
    const [error] = errorsFor("[x](nope:x)");
    expect(error?.title).toBe("BROKEN LINK");
    expect(error?.message).toContain("`nope`");
    expect(error?.hint).toContain("pages");
    expect(error?.hint).toContain("posts");
  });

  test("resolves a relative .md path against the linking document", () => {
    expect(linkIn("[x](../pages/about.md)")).toMatchObject({
      type: "sheafLink",
      collection: "pages",
      slug: "about",
    });
    expect(linkIn("[x](./hello-world.md)")).toMatchObject({
      type: "sheafLink",
      collection: "posts",
      slug: "hello-world",
    });
  });

  test("keeps the fragment of a relative link", () => {
    expect(linkIn("[x](../pages/about.md#team)")).toMatchObject({
      type: "sheafLink",
      slug: "about",
      fragment: "team",
    });
  });

  test("reports a relative link to a missing document", () => {
    const [error] = errorsFor("[x](./missing.md)");
    expect(error?.title).toBe("BROKEN LINK");
    expect(error?.message).toContain("./missing.md");
  });

  test("leaves URLs, fragments and other relative paths alone", () => {
    for (const url of [
      "https://elm-lang.org",
      "tel:+351000000",
      "#section",
      "/about/",
      "photo.png",
    ]) {
      expect(linkIn(`[x](${url})`)).toMatchObject({ type: "link", url });
    }
  });

  test("decodes percent-encoded non-ASCII slugs and paths", () => {
    for (const url of ["./café-notes.md", "posts:café-notes"]) {
      expect(linkIn(`[x](${url})`)).toMatchObject({
        type: "sheafLink",
        collection: "posts",
        slug: "café-notes",
      });
    }
  });

  test("reports an invalid percent-encoding", () => {
    const [error] = errorsFor("[x](posts:%E0)");
    expect(error?.title).toBe("BROKEN LINK");
  });

  test("reports every broken link in a document", () => {
    expect(errorsFor("[a](posts:nope) and [b](pages:nope)")).toHaveLength(2);
  });

  test("locates a reference-style link at its use", () => {
    const [error] = errorsFor("See [x][r].\n\n[r]: posts:helo-world\n");
    expect(error?.title).toBe("BROKEN LINK");
    expect(error?.span).toEqual({
      start: { line: 1, column: 5 },
      end: { line: 1, column: 11 },
    });
  });
});
