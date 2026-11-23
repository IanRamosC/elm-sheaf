import type { DocumentDate } from "../content/dates";
import type { SourceDocument } from "../content/document";
import type { Diagnostic, Span } from "../diagnostics/diagnostic";
import type { Node } from "../markdown/tree";
import { err, ok, type Result } from "../result";

/** Bumped whenever the JSON exchanged with the Elm worker changes shape. */
export const PROTOCOL_VERSION = 1;

export type BuildMode = "production" | "drafts";

export type BuildInfo = {
  siteUrl: string;
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
  build: BuildInfo;
  documents: RequestDocument[];
};

/** `path` is relative to `dist/` and does not include the base path. */
export type Page = { path: string; html: string };

export type Response = { pages: Page[]; diagnostics: Diagnostic[] };

function wireDate(date: DocumentDate | undefined): WireDate | null {
  return date
    ? { posixMillis: date.instant.getTime(), isoDate: date.isoDate }
    : null;
}

/** A loaded document together with the Markdown tree parsed from its body. */
export type ParsedDocument = { source: SourceDocument; tree: Node };

export function encodeRequest(
  build: BuildInfo,
  documents: ParsedDocument[],
): Request {
  return {
    protocolVersion: PROTOCOL_VERSION,
    build,
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

export function decodeResponse(json: unknown): Result<Response, string> {
  const raw = decodeRecord(json, "response");
  if (!raw.ok) {
    return raw;
  }
  const pages = decodeList(raw.value.pages, "pages", decodePage);
  const diagnostics = decodeList(
    raw.value.diagnostics,
    "diagnostics",
    decodeDiagnostic,
  );
  if (!pages.ok) {
    return pages;
  }
  return diagnostics.ok
    ? ok({ pages: pages.value, diagnostics: diagnostics.value })
    : diagnostics;
}
