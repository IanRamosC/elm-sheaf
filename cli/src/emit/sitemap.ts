import type { SitemapEntry } from "../elm/protocol";
import { xmlUrl } from "./xml";

/** Renders the sitemap protocol's `urlset` for the given pages. */
export function sitemapXml(entries: SitemapEntry[]): string {
  const urls = entries.map(({ url, lastModified }) => {
    const lastmod =
      lastModified === null
        ? ""
        : `<lastmod>${new Date(lastModified).toISOString()}</lastmod>`;
    return `  <url><loc>${xmlUrl(url)}</loc>${lastmod}</url>`;
  });
  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">',
    ...urls,
    "</urlset>",
    "",
  ].join("\n");
}
