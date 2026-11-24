import type { DocumentDate } from "../content/dates";
import type { SourceDocument } from "../content/document";
import type { BuildMode } from "../content/load";
import type { GroupSlug } from "../content/slug";
import type { Diagnostic, Span } from "../diagnostics/diagnostic";
import type { Node } from "../markdown/tree";
import { err, ok, type Result } from "../result";

/** Bumped whenever the JSON exchanged with the Elm worker changes shape. */
export const PROTOCOL_VERSION = 3;

export type BuildInfo = {
  siteUrl: string;
  basePath: string;
  mode: BuildMode;
};

/**
 * What the worker is told about the build. `origin` has no trailing slash, so
 * an absolute URL is `origin + url`, where `url` already has the base path.
 */
export type WireBuild = {
  siteUrl: string;
  origin: string;
  basePath: string;
  mode: BuildMode;
};

/** A date as the worker needs it: a moment to compare and the calendar date to show. */
export type WireDate = { posixMillis: number; isoDate: string };

export type RequestDocument = {
  id: string;
  collection: string;
  sourcePath: string;
  slug: string;
  date: WireDate | null;
  updated: WireDate | null;
  draft: boolean;
  excluded: boolean;
  frontmatter: SourceDocument["frontmatter"];
  frontmatterPositions: SourceDocument["frontmatterPositions"];
  tree: Node;
};

export type Request = {
  protocolVersion: typeof PROTOCOL_VERSION;
  build: WireBuild;
  /** Every string value in frontmatter, with the slug the worker groups it by. */
  slugs: GroupSlug[];
  /** Every folder in `content/`, including empty ones, which send no documents. */
  collections: string[];
  documents: RequestDocument[];
};

/** `path` is relative to `dist/` and does not include the base path. */
export type Page = { path: string; html: string };

export type SiteMetadata = {
  title: string;
  description: string;
  author: { name: string; email: string | null };
  language: string;
};

/** An entry of a feed. `url` is absolute and the dates are POSIX milliseconds. */
export type FeedItem = {
  documentId: string;
  url: string;
  title: string;
  summary: string | null;
  html: string;
  date: number;
  updated: number;
};

/** The paths are relative to `dist/` and do not include the base path. */
export type Feed = { rss: string; atom: string; items: FeedItem[] };

export type SitemapEntry = { url: string; lastModified: number | null };

export type Response = {
  site: SiteMetadata;
  pages: Page[];
  feeds: Feed[];
  sitemap: SitemapEntry[];
  diagnostics: Diagnostic[];
};

function wireDate(date: DocumentDate | undefined): WireDate | null {
  return date
    ? { posixMillis: date.instant.getTime(), isoDate: date.isoDate }
    : null;
}

/** A loaded document together with the Markdown tree parsed from its body. */
export type ParsedDocument = { source: SourceDocument; tree: Node };

export function encodeRequest(
  build: BuildInfo,
  collections: string[],
  documents: ParsedDocument[],
  slugs: GroupSlug[],
): Request {
  return {
    protocolVersion: PROTOCOL_VERSION,
    build: {
      siteUrl: build.siteUrl,
      origin: new URL(build.siteUrl).origin,
      basePath: build.basePath,
      mode: build.mode,
    },
    slugs,
    collections,
    documents: documents.map(({ source, tree }) => ({
      id: source.id,
      collection: source.collection,
      sourcePath: source.sourcePath,
      slug: source.slug,
      date: wireDate(source.date),
      updated: wireDate(source.updated),
      draft: source.draft,
      excluded: source.excluded,
      frontmatter: source.frontmatter,
      frontmatterPositions: source.frontmatterPositions,
      tree,
    })),
  };
}

// The response comes from our own Elm code, so these checks exist to catch a
// version mismatch or a bug in the encoder, and name the field at fault.

type Decoded<T> = Result<T, string>;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function decodeText(value: unknown, path: string): Decoded<string> {
  return typeof value === "string"
    ? ok(value)
    : err(`${path} must be a string`);
}

function decodeNumber(value: unknown, path: string): Decoded<number> {
  return typeof value === "number"
    ? ok(value)
    : err(`${path} must be a number`);
}

function decodeNullable<T>(
  value: unknown,
  path: string,
  decode: (present: unknown, path: string) => Decoded<T>,
): Decoded<T | null> {
  return value === null ? ok(null) : decode(value, path);
}

function decodeRecord(
  value: unknown,
  path: string,
): Decoded<Record<string, unknown>> {
  return isRecord(value) ? ok(value) : err(`${path} must be an object`);
}

function decodeList<T>(
  value: unknown,
  path: string,
  decodeItem: (item: unknown, itemPath: string) => Decoded<T>,
): Decoded<T[]> {
  if (!Array.isArray(value)) {
    return err(`${path} must be a list`);
  }
  const items: T[] = [];
  for (const [index, item] of value.entries()) {
    const decoded = decodeItem(item, `${path}[${index}]`);
    if (!decoded.ok) {
      return decoded;
    }
    items.push(decoded.value);
  }
  return ok(items);
}

function decodeOptional<T>(
  value: unknown,
  path: string,
  decode: (present: unknown, path: string) => Decoded<T>,
): Decoded<T | undefined> {
  return value === undefined ? ok(undefined) : decode(value, path);
}

function decodePosition(value: unknown, path: string) {
  const position = decodeRecord(value, path);
  if (!position.ok) {
    return position;
  }
  const line = decodeNumber(position.value.line, `${path}.line`);
  const column = decodeNumber(position.value.column, `${path}.column`);
  if (!line.ok) {
    return line;
  }
  return column.ok ? ok({ line: line.value, column: column.value }) : column;
}

function decodeSpan(value: unknown, path: string): Decoded<Span> {
  const span = decodeRecord(value, path);
  if (!span.ok) {
    return span;
  }
  const start = decodePosition(span.value.start, `${path}.start`);
  const end = decodePosition(span.value.end, `${path}.end`);
  if (!start.ok) {
    return start;
  }
  return end.ok ? ok({ start: start.value, end: end.value }) : end;
}

function decodeDiagnostic(value: unknown, path: string): Decoded<Diagnostic> {
  const raw = decodeRecord(value, path);
  if (!raw.ok) {
    return raw;
  }
  const { severity } = raw.value;
  if (severity !== "error" && severity !== "warning") {
    return err(`${path}.severity must be "error" or "warning"`);
  }
  const title = decodeText(raw.value.title, `${path}.title`);
  const message = decodeText(raw.value.message, `${path}.message`);
  const sourcePath = decodeOptional(
    raw.value.sourcePath,
    `${path}.sourcePath`,
    decodeText,
  );
  const span = decodeOptional(raw.value.span, `${path}.span`, decodeSpan);
  const hint = decodeOptional(raw.value.hint, `${path}.hint`, decodeText);
  if (!title.ok) return title;
  if (!message.ok) return message;
  if (!sourcePath.ok) return sourcePath;
  if (!span.ok) return span;
  if (!hint.ok) return hint;

  const diagnostic: Diagnostic = {
    severity,
    title: title.value,
    message: message.value,
  };
  if (sourcePath.value !== undefined) diagnostic.sourcePath = sourcePath.value;
  if (span.value !== undefined) diagnostic.span = span.value;
  if (hint.value !== undefined) diagnostic.hint = hint.value;
  return ok(diagnostic);
}

function decodePage(value: unknown, path: string): Decoded<Page> {
  const raw = decodeRecord(value, path);
  if (!raw.ok) {
    return raw;
  }
  const pagePath = decodeText(raw.value.path, `${path}.path`);
  const html = decodeText(raw.value.html, `${path}.html`);
  if (!pagePath.ok) {
    return pagePath;
  }
  return html.ok ? ok({ path: pagePath.value, html: html.value }) : html;
}

function decodeSiteMetadata(
  value: unknown,
  path: string,
): Decoded<SiteMetadata> {
  const raw = decodeRecord(value, path);
  if (!raw.ok) return raw;
  const title = decodeText(raw.value.title, `${path}.title`);
  const description = decodeText(raw.value.description, `${path}.description`);
  const language = decodeText(raw.value.language, `${path}.language`);
  const author = decodeRecord(raw.value.author, `${path}.author`);
  if (!title.ok) return title;
  if (!description.ok) return description;
  if (!author.ok) return author;
  const name = decodeText(author.value.name, `${path}.author.name`);
  const email = decodeNullable(
    author.value.email,
    `${path}.author.email`,
    decodeText,
  );
  if (!name.ok) return name;
  if (!email.ok) return email;
  if (!language.ok) return language;
  return ok({
    title: title.value,
    description: description.value,
    author: { name: name.value, email: email.value },
    language: language.value,
  });
}

function decodeFeedItem(value: unknown, path: string): Decoded<FeedItem> {
  const raw = decodeRecord(value, path);
  if (!raw.ok) return raw;
  const documentId = decodeText(raw.value.documentId, `${path}.documentId`);
  const url = decodeText(raw.value.url, `${path}.url`);
  const title = decodeText(raw.value.title, `${path}.title`);
  const summary = decodeNullable(
    raw.value.summary,
    `${path}.summary`,
    decodeText,
  );
  const html = decodeText(raw.value.html, `${path}.html`);
  const date = decodeNumber(raw.value.date, `${path}.date`);
  const updated = decodeNumber(raw.value.updated, `${path}.updated`);
  if (!documentId.ok) return documentId;
  if (!url.ok) return url;
  if (!title.ok) return title;
  if (!summary.ok) return summary;
  if (!html.ok) return html;
  if (!date.ok) return date;
  if (!updated.ok) return updated;
  return ok({
    documentId: documentId.value,
    url: url.value,
    title: title.value,
    summary: summary.value,
    html: html.value,
    date: date.value,
    updated: updated.value,
  });
}

function decodeFeed(value: unknown, path: string): Decoded<Feed> {
  const raw = decodeRecord(value, path);
  if (!raw.ok) return raw;
  const rss = decodeText(raw.value.rss, `${path}.rss`);
  const atom = decodeText(raw.value.atom, `${path}.atom`);
  const items = decodeList(raw.value.items, `${path}.items`, decodeFeedItem);
  if (!rss.ok) return rss;
  if (!atom.ok) return atom;
  return items.ok
    ? ok({ rss: rss.value, atom: atom.value, items: items.value })
    : items;
}

function decodeSitemapEntry(
  value: unknown,
  path: string,
): Decoded<SitemapEntry> {
  const raw = decodeRecord(value, path);
  if (!raw.ok) return raw;
  const url = decodeText(raw.value.url, `${path}.url`);
  const lastModified = decodeNullable(
    raw.value.lastModified,
    `${path}.lastModified`,
    decodeNumber,
  );
  if (!url.ok) return url;
  return lastModified.ok
    ? ok({ url: url.value, lastModified: lastModified.value })
    : lastModified;
}

export function decodeResponse(json: unknown): Result<Response, string> {
  const raw = decodeRecord(json, "response");
  if (!raw.ok) {
    return raw;
  }
  const site = decodeSiteMetadata(raw.value.site, "site");
  const pages = decodeList(raw.value.pages, "pages", decodePage);
  const feeds = decodeList(raw.value.feeds, "feeds", decodeFeed);
  const sitemap = decodeList(raw.value.sitemap, "sitemap", decodeSitemapEntry);
  const diagnostics = decodeList(
    raw.value.diagnostics,
    "diagnostics",
    decodeDiagnostic,
  );
  if (!site.ok) return site;
  if (!pages.ok) return pages;
  if (!feeds.ok) return feeds;
  if (!sitemap.ok) return sitemap;
  if (!diagnostics.ok) return diagnostics;
  return ok({
    site: site.value,
    pages: pages.value,
    feeds: feeds.value,
    sitemap: sitemap.value,
    diagnostics: diagnostics.value,
  });
}
