import type { Feed, SiteMetadata } from "../elm/protocol";
import { escapeXml, xmlUrl } from "./xml";

/** `site` is the origin plus base path; `feed` is this feed's own URL. */
export type FeedUrls = { site: string; feed: string };

const HEADER = '<?xml version="1.0" encoding="UTF-8"?>';

/** The feed's last change: its newest item, or the build time when it is empty. */
function lastChange(feed: Feed, now: Date): Date {
  if (feed.items.length === 0) return now;
  return new Date(Math.max(...feed.items.map(({ updated }) => updated)));
}

/** Renders an RSS 2.0 document with the full HTML of each item. */
export function rssFeed(
  feed: Feed,
  urls: FeedUrls,
  metadata: SiteMetadata,
  now: Date,
): string {
  const { author } = metadata;
  const items = feed.items.map(
    (item) =>
      `    <item>
      <title>${escapeXml(item.title)}</title>
      <link>${xmlUrl(item.url)}</link>
      <guid isPermaLink="true">${xmlUrl(item.url)}</guid>
      <pubDate>${new Date(item.date).toUTCString()}</pubDate>
      <description>${escapeXml(item.html)}</description>
    </item>`,
  );
  const editor =
    author.email === null
      ? []
      : [
          `    <managingEditor>${escapeXml(author.email)} (${escapeXml(author.name)})</managingEditor>`,
        ];
  return [
    HEADER,
    '<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">',
    "  <channel>",
    `    <title>${escapeXml(metadata.title)}</title>`,
    `    <link>${xmlUrl(urls.site)}</link>`,
    `    <description>${escapeXml(metadata.description)}</description>`,
    `    <language>${escapeXml(metadata.language)}</language>`,
    `    <lastBuildDate>${lastChange(feed, now).toUTCString()}</lastBuildDate>`,
    `    <atom:link href="${xmlUrl(urls.feed)}" rel="self" type="application/rss+xml"/>`,
    ...editor,
    ...items,
    "  </channel>",
    "</rss>",
    "",
  ].join("\n");
}

/** Renders an Atom document with the full HTML of each entry. */
export function atomFeed(
  feed: Feed,
  urls: FeedUrls,
  metadata: SiteMetadata,
  now: Date,
): string {
  const { author } = metadata;
  const email =
    author.email === null ? "" : `<email>${escapeXml(author.email)}</email>`;
  const entries = feed.items.map((item) => {
    const summary =
      item.summary === null
        ? []
        : [`    <summary>${escapeXml(item.summary)}</summary>`];
    return [
      "  <entry>",
      `    <id>${xmlUrl(item.url)}</id>`,
      `    <title>${escapeXml(item.title)}</title>`,
      `    <link href="${xmlUrl(item.url)}"/>`,
      `    <published>${new Date(item.date).toISOString()}</published>`,
      `    <updated>${new Date(item.updated).toISOString()}</updated>`,
      ...summary,
      `    <content type="html">${escapeXml(item.html)}</content>`,
      "  </entry>",
    ].join("\n");
  });
  return [
    HEADER,
    '<feed xmlns="http://www.w3.org/2005/Atom">',
    `  <id>${xmlUrl(urls.feed)}</id>`,
    `  <link rel="self" href="${xmlUrl(urls.feed)}"/>`,
    `  <link rel="alternate" href="${xmlUrl(urls.site)}"/>`,
    `  <title>${escapeXml(metadata.title)}</title>`,
    `  <subtitle>${escapeXml(metadata.description)}</subtitle>`,
    `  <updated>${lastChange(feed, now).toISOString()}</updated>`,
    `  <author><name>${escapeXml(author.name)}</name>${email}</author>`,
    ...entries,
    "</feed>",
    "",
  ].join("\n");
}
