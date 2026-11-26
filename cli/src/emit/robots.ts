/** The default `robots.txt`: every crawler may read everything, and the sitemap is named. */
export function robotsTxt(sitemapUrl: string): string {
  return `User-agent: *\nAllow: /\n\nSitemap: ${sitemapUrl}\n`;
}

/**
 * Whether a site provides its own `robots.txt`, as a file or as a folder that
 * would hold it. Paths are compared lowercased, as the clash check does.
 */
export function providesRobots(paths: string[]): boolean {
  return paths.some((path) => {
    const lower = path.toLowerCase();
    return lower === "robots.txt" || lower.startsWith("robots.txt/");
  });
}
