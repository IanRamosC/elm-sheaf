import { describe, expect, test } from "bun:test";
import type { Feed, FeedItem, SiteMetadata } from "../../src/elm/protocol";
import { atomFeed, rssFeed } from "../../src/emit/feeds";

const metadata: SiteMetadata = {
  title: "Site & Co",
  description: "Words",
  author: { name: "Ann", email: "ann@example.com" },
  language: "en",
};
const urls = {
  site: "https://example.com/a&b/",
  feed: "https://example.com/a&b/feed.xml",
};

function item(overrides: Partial<FeedItem> = {}): FeedItem {
  return {
    documentId: "posts/one",
    url: "https://example.com/a&b/posts/one/",
    title: `Tom & "Jerry" <3`,
    summary: "ends ]]> here",
    html: "<p>a &amp; b</p>",
    date: Date.UTC(2026, 0, 1),
    updated: Date.UTC(2026, 0, 3),
    ...overrides,
  };
}

function feed(items: FeedItem[]): Feed {
  return { rss: "feed.xml", atom: "atom.xml", title: "Site & Co · Elm", items };
}

describe("rssFeed", () => {
  const xml = rssFeed(feed([item()]), urls, metadata);

  test("titles the channel after the feed", () => {
    expect(xml).toContain("<title>Site &amp; Co · Elm</title>");
  });

  test("escapes text without CDATA", () => {
    expect(xml).toContain("Tom &amp; &quot;Jerry&quot; &lt;3");
    expect(xml).toContain("&lt;p&gt;a &amp;amp; b&lt;/p&gt;");
    expect(xml).not.toContain("CDATA");
  });

  test("describes the channel and items", () => {
    expect(xml).toContain('xmlns:atom="http://www.w3.org/2005/Atom"');
    expect(xml).toContain("<link>https://example.com/a&amp;b/</link>");
    expect(xml).toContain(
      '<atom:link href="https://example.com/a&amp;b/feed.xml" rel="self" type="application/rss+xml"/>',
    );
    expect(xml).toContain(
      "<managingEditor>ann@example.com (Ann)</managingEditor>",
    );
    expect(xml).toContain('<guid isPermaLink="true">');
    expect(xml).toContain("<pubDate>Thu, 01 Jan 2026 00:00:00 GMT</pubDate>");
    expect(xml).toContain(
      "<lastBuildDate>Sat, 03 Jan 2026 00:00:00 GMT</lastBuildDate>",
    );
  });

  test("leaves out the build date of an empty feed, and omits the editor without an email", () => {
    const empty = rssFeed(feed([]), urls, {
      ...metadata,
      author: { name: "Ann", email: null },
    });
    expect(empty).not.toContain("lastBuildDate");
    expect(empty).not.toContain("managingEditor");
  });

  test("strips characters XML forbids", () => {
    const dirty = rssFeed(feed([item({ html: "a\u000cb" })]), urls, metadata);
    expect(dirty).not.toContain("\u000c");
  });
});

describe("atomFeed", () => {
  test("titles the feed after the feed, not the site", () => {
    expect(atomFeed(feed([item()]), urls, metadata)).toContain(
      "<title>Site &amp; Co · Elm</title>",
    );
  });

  test("separates published and updated", () => {
    const xml = atomFeed(feed([item()]), urls, metadata);
    expect(xml).toContain("<published>2026-01-01T00:00:00.000Z</published>");
    expect(xml).toContain("<updated>2026-01-03T00:00:00.000Z</updated>");
    expect(xml).toContain(
      '<content type="html">&lt;p&gt;a &amp;amp; b&lt;/p&gt;</content>',
    );
    expect(xml).toContain("<summary>ends ]]&gt; here</summary>");
    expect(xml).toContain(
      '<link rel="self" href="https://example.com/a&amp;b/feed.xml"/>',
    );
    expect(xml).toContain("<email>ann@example.com</email>");
  });

  test("gives an empty feed a fixed date, and skips an absent summary", () => {
    expect(atomFeed(feed([]), urls, metadata)).toContain(
      "<updated>1970-01-01T00:00:00.000Z</updated>",
    );
    expect(
      atomFeed(feed([item({ summary: null })]), urls, metadata),
    ).not.toContain("<summary>");
  });
});
