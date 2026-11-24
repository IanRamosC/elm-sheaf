import { describe, expect, test } from "bun:test";
import { sitemapXml } from "../../src/emit/sitemap";
import { absoluteUrl, escapeXml } from "../../src/emit/xml";

describe("escapeXml", () => {
  test("escapes markup characters and drops forbidden control characters", () => {
    expect(escapeXml(`Tom & "Jerry" <3 ]]> 'x'`)).toBe(
      "Tom &amp; &quot;Jerry&quot; &lt;3 ]]&gt; &apos;x&apos;",
    );
    expect(escapeXml("a\u0000b\u000cc\u001fd\uFFFEe\tf\ng")).toBe(
      "abcde\tf\ng",
    );
  });
});

describe("absoluteUrl", () => {
  test("percent-encodes non-ASCII", () => {
    expect(absoluteUrl("https://example.com/tags/日本/")).toBe(
      "https://example.com/tags/%E6%97%A5%E6%9C%AC/",
    );
  });
});

describe("sitemapXml", () => {
  test("lists encoded locations with optional lastmod", () => {
    const xml = sitemapXml([
      { url: "https://example.com/tags/日本/", lastModified: null },
      { url: "https://example.com/a&b/", lastModified: Date.UTC(2026, 0, 2) },
    ]);
    expect(xml).toStartWith('<?xml version="1.0" encoding="UTF-8"?>\n');
    expect(xml).toContain(
      "<loc>https://example.com/tags/%E6%97%A5%E6%9C%AC/</loc>",
    );
    expect(xml).toContain(
      "<loc>https://example.com/a&amp;b/</loc><lastmod>2026-01-02T00:00:00.000Z</lastmod>",
    );
    expect(xml).toContain(
      '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">',
    );
  });
});
