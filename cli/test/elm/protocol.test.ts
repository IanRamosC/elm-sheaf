import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { embeddedFixtureModule } from "../../scripts/embed-protocol-fixtures";
import type { SourceDocument } from "../../src/content/document";
import {
  decodeResponse,
  encodeRequest,
  PROTOCOL_VERSION,
  type Request,
  type Response,
} from "../../src/elm/protocol";
import { checkLinks } from "../../src/markdown/links";
import { parseMarkdown } from "../../src/markdown/parse";

const FIXTURES = join(import.meta.dir, "../../../tests/fixtures/protocol");

function fixture(name: string): unknown {
  return JSON.parse(readFileSync(join(FIXTURES, `${name}.json`), "utf8"));
}

/** Rebuilds what the loader and parser would hand to `encodeRequest`. */
function sourcesOf(request: Request) {
  return request.documents.map(({ tree, date, updated, ...rest }) => {
    const source: SourceDocument = {
      ...rest,
      body: "",
      bodyStartLine: 1,
    };
    if (date) {
      source.date = {
        instant: new Date(date.posixMillis),
        isoDate: date.isoDate,
      };
    }
    if (updated) {
      source.updated = {
        instant: new Date(updated.posixMillis),
        isoDate: updated.isoDate,
      };
    }
    return { source, tree };
  });
}

describe("encodeRequest", () => {
  for (const name of ["minimal-request", "all-nodes-request"]) {
    test(`produces the ${name} fixture`, () => {
      const expected = fixture(name) as Request;
      expect(PROTOCOL_VERSION).toBe(2);
      expect(
        encodeRequest(
          expected.build,
          expected.collections,
          sourcesOf(expected),
          expected.slugs,
        ),
      ).toEqual(expected);
    });
  }

  test("sends the origin of the site URL, without its base path", () => {
    const request = encodeRequest(
      {
        siteUrl: "https://example.com/blog/",
        basePath: "/blog/",
        mode: "production",
      },
      [],
      [],
      [],
    );
    expect(request.build.origin).toBe("https://example.com");
  });
});

describe("the all-nodes fixture tree", () => {
  test("is what the parser and link checker produce for all-nodes.md", () => {
    const [fixtureDocument] = (fixture("all-nodes-request") as Request)
      .documents;
    if (fixtureDocument === undefined)
      throw new Error("fixture has no document");
    const document: SourceDocument = {
      id: fixtureDocument.id,
      collection: fixtureDocument.collection,
      sourcePath: fixtureDocument.sourcePath,
      slug: fixtureDocument.slug,
      draft: false,
      excluded: false,
      frontmatter: {},
      frontmatterPositions: {},
      body: readFileSync(join(FIXTURES, "all-nodes.md"), "utf8"),
      bodyStartLine: 1,
    };
    const parsed = parseMarkdown(document);
    if (!parsed.ok) throw new Error("the sample does not parse");
    const checked = checkLinks(parsed.value, document, [document]);
    expect(checked).toEqual({ ok: true, value: fixtureDocument.tree });
  });
});

describe("decodeResponse", () => {
  test("decodes the response fixture", () => {
    const result = decodeResponse(fixture("response-with-diagnostic"));
    expect(result).toEqual({
      ok: true,
      value: fixture("response-with-diagnostic") as Response,
    });
  });

  test("decodes a response whose optional fields are null", () => {
    const result = decodeResponse(fixture("response-with-diagnostic"));
    if (!result.ok) throw new Error(result.error);
    expect(result.value.site.author.email).toBeNull();
    expect(result.value.feeds[0]?.items[0]?.summary).toBeNull();
    expect(result.value.sitemap[1]?.lastModified).toBeNull();
  });

  test("rejects a response that is not an object", () => {
    expect(decodeResponse("nope").ok).toBe(false);
  });

  test("names the field that is wrong", () => {
    const result = decodeResponse({
      ...(fixture("response-with-diagnostic") as Response),
      pages: [{ path: "a/index.html" }],
    });
    expect(result).toEqual({
      ok: false,
      error: "pages[0].html must be a string",
    });
  });

  test("rejects an unknown severity", () => {
    const result = decodeResponse({
      ...(fixture("response-with-diagnostic") as Response),
      diagnostics: [{ severity: "fatal", title: "t", message: "m" }],
    });
    expect(result).toEqual({
      ok: false,
      error: 'diagnostics[0].severity must be "error" or "warning"',
    });
  });
});

describe("the embedded fixtures", () => {
  test("match the committed tests/ProtocolFixtures.elm", () => {
    const committed = readFileSync(
      join(FIXTURES, "../../ProtocolFixtures.elm"),
      "utf8",
    );
    if (embeddedFixtureModule() !== committed) {
      throw new Error("Run bun run embed-fixtures");
    }
  });
});
