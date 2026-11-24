// XML 1.0 forbids these control characters even as numeric references, so
// they are dropped; a stray form feed in a post would otherwise make the
// whole feed unparseable.
// biome-ignore lint/suspicious/noControlCharactersInRegex: matching them is the point
const FORBIDDEN = /[\u0000-\u0008\u000B\u000C\u000E-\u001F￾￿]/g;

const ESCAPES: Record<string, string> = {
  "&": "&amp;",
  "<": "&lt;",
  ">": "&gt;",
  '"': "&quot;",
  "'": "&apos;",
};

/** Makes text safe for XML content and attribute values. */
export function escapeXml(text: string): string {
  return text
    .replace(FORBIDDEN, "")
    .replace(/[&<>"']/g, (character) => ESCAPES[character] ?? character);
}

/** Normalises a URL the way a browser sends it, which percent-encodes non-ASCII. */
export function absoluteUrl(url: string): string {
  return new URL(url).href;
}

/** A URL ready to sit inside XML text or an attribute. */
export function xmlUrl(url: string): string {
  return escapeXml(absoluteUrl(url));
}
