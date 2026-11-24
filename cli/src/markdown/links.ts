import { posix } from "node:path";
import type { SourceDocument } from "../content/document";
import type { ContentFiles } from "../content/files";
import type { Diagnostic, Position, Span } from "../diagnostics/diagnostic";
import { collect, err, ok, type Result } from "../result";
import { suggestions } from "../suggest";
import { URL_SCHEMES } from "../url-schemes";
import type { Node } from "./tree";

type Link = Extract<Node, { type: "link" }>;

const MAX_SUGGESTIONS = 3;
const SCHEME_PREFIX = /^([A-Za-z][A-Za-z0-9+.-]*):/;

/**
 * Checks every Markdown link that points at another document, either as
 * `<collection>:<slug>[#fragment]` or as a path to its `.md` file (relative,
 * or from `content/` when it starts with `/`), and rewrites it into a
 * `sheafLink`. A relative link to any other file in `content/` is an error,
 * because only documents are published. Other links are left as they are.
 * Every broken link is reported, not just the first, at its destination.
 */
export function checkLinks(
  tree: Node,
  document: SourceDocument,
  all: SourceDocument[],
  files: ContentFiles,
): Result<Node, Diagnostic[]> {
  const source = new BodySource(document);
  const bySourcePath = new Map(all.map((other) => [other.sourcePath, other]));
  const slugsByCollection = new Map<string, string[]>();
  for (const { collection, slug } of all) {
    slugsByCollection.set(collection, [
      ...(slugsByCollection.get(collection) ?? []),
      slug,
    ]);
  }

  function problem(
    title: string,
    link: Link,
    message: string,
    hint?: string,
  ): Diagnostic {
    return {
      severity: "error",
      title,
      message,
      sourcePath: document.sourcePath,
      span: source.destinationSpan(link),
      ...(hint === undefined ? {} : { hint }),
    };
  }

  function broken(link: Link, message: string, hint?: string): Diagnostic {
    return problem("BROKEN LINK", link, message, hint);
  }

  function sheafLink(
    link: Link,
    collection: string,
    slug: string,
    fragment: string | undefined,
  ): Node {
    return {
      type: "sheafLink",
      position: link.position,
      collection,
      slug,
      ...(fragment ? { fragment } : {}),
      ...(link.title === undefined ? {} : { title: link.title }),
      children: link.children,
    };
  }

  function checkCollectionLink(
    link: Link,
    collection: string,
    target: string,
  ): Result<Node, Diagnostic[]> {
    const [encodedSlug = "", fragment] = splitFragment(target);
    const written = `${collection}:${decodeOr(encodedSlug)}`;
    const slug = decode(encodedSlug);
    if (slug === undefined) {
      return err([
        broken(
          link,
          `This document links to \`${written}\`, which is not validly percent-encoded.`,
        ),
      ]);
    }
    const slugs = slugsByCollection.get(collection);
    if (!slugs) {
      return err([
        broken(
          link,
          `This document links to \`${written}\`, but there is no collection named \`${collection}\`.`,
          `The collections are:\n\n${indented([...slugsByCollection.keys()])}`,
        ),
      ]);
    }
    if (!slugs.includes(slug)) {
      const similar = suggestions(slug, slugs, MAX_SUGGESTIONS).map(
        (candidate) => `${collection}:${candidate}`,
      );
      return err([
        broken(
          link,
          `This document links to \`${written}\`, but no document in \`${collection}\` has that slug.`,
          similar.length > 0
            ? `Did you mean one of these?\n\n${indented(similar)}`
            : undefined,
        ),
      ]);
    }
    return ok(sheafLink(link, collection, slug, fragment));
  }

  function checkPathLink(
    link: Link,
    encodedPath: string,
    fragment: string | undefined,
  ): Result<Node, Diagnostic[]> {
    const path = decode(encodedPath);
    if (path === undefined) {
      return err([
        broken(
          link,
          `This document links to \`${encodedPath}\`, which is not validly percent-encoded.`,
        ),
      ]);
    }
    const isDocument = path.endsWith(".md");
    const base = path.startsWith("/")
      ? "content"
      : posix.dirname(document.sourcePath);
    const target = posix.join(base, path);
    const lookup = files.find(target);
    if (lookup === undefined) {
      return err([
        broken(
          link,
          `This document links to \`${path}\`, but no such ${isDocument ? "document" : "file"} exists.`,
        ),
      ]);
    }
    if ("caseOf" in lookup) {
      return err([
        problem(
          "CASE MISMATCH",
          link,
          `The file is \`${posix.relative(base, lookup.caseOf)}\`, but this refers to \`${posix.relative(base, target)}\`. Linux treats them as different files, so the site would fail to build there.`,
        ),
      ]);
    }
    if (!isDocument) {
      const name = posix.basename(lookup.found);
      return err([
        problem(
          "LOCAL FILE LINK",
          link,
          `This document links to \`${path}\`, a file in \`content/\`. Only the documents in \`content/\` are published, so the link would be broken on the site.`,
          `Move \`${name}\` to \`static/\` and link to it with a path starting with \`/\`, such as \`/${name}\`.`,
        ),
      ]);
    }
    const linked = bySourcePath.get(lookup.found);
    if (!linked) {
      throw new Error(`${lookup.found} is in content/ but is not a document`);
    }
    return ok(sheafLink(link, linked.collection, linked.slug, fragment));
  }

  function checkLink(link: Link): Result<Node, Diagnostic[]> {
    const scheme = SCHEME_PREFIX.exec(link.url)?.[1];
    if (scheme !== undefined) {
      return URL_SCHEMES.includes(scheme.toLowerCase())
        ? ok(link)
        : checkCollectionLink(link, scheme, link.url.slice(scheme.length + 1));
    }
    const [beforeFragment, fragment] = splitFragment(link.url);
    const [encodedPath = ""] = beforeFragment.split("?");
    // A root-relative link to anything but a document points into `static/`,
    // and a path without an extension, such as `../b/`, is a page URL.
    const checked = encodedPath.endsWith(".md")
      ? !encodedPath.startsWith("//")
      : !encodedPath.startsWith("/") && posix.extname(encodedPath) !== "";
    return checked ? checkPathLink(link, encodedPath, fragment) : ok(link);
  }

  function check(node: Node): Result<Node, Diagnostic[]> {
    if (node.type === "link") {
      const checked = checkLink(node);
      if (!checked.ok) return checked;
      node = checked.value;
    }
    if (!("children" in node)) return ok(node);
    const children = collect(node.children.map(check));
    if (!children.ok) return children;
    return ok({ ...node, children: children.value } as Node);
  }

  return check(tree);
}

/**
 * A document's body, for finding where in the file a link's destination is
 * written. Tree positions are file lines and columns; the body starts at
 * `bodyStartLine`.
 */
class BodySource {
  private readonly text: string;
  private readonly lineOffset: number;
  /** The offset in `text` at which each line starts. */
  private readonly lineStarts = [0];

  constructor(document: SourceDocument) {
    this.text = document.body;
    this.lineOffset = document.bodyStartLine - 1;
    for (const ending of this.text.matchAll(/\r\n|\r|\n/g)) {
      this.lineStarts.push(ending.index + ending[0].length);
    }
  }

  /**
   * Where the link's destination is written: inside the `<…>` of an
   * autolink, and after the `](` of an inline link. A reference-style link's
   * destination is in its definition, which other links may share, so it
   * keeps its whole span, as do literal autolinks such as `www.example.com`.
   */
  destinationSpan(link: Link): Span {
    const start = this.offsetOf(link.position.start);
    const end = this.offsetOf(link.position.end);
    const written = this.text.slice(start, end);
    if (written.startsWith("<") && written.endsWith(">")) {
      return this.spanBetween(start + 1, end - 1);
    }
    if (!written.startsWith("[") || !written.includes("](")) {
      return link.position;
    }
    const lastChild = link.children.at(-1);
    const labelEnd = lastChild
      ? this.offsetOf(lastChild.position.end)
      : start + 1;
    let from = this.text.indexOf("](", labelEnd) + 2;
    while (from < end && /\s/.test(this.text.charAt(from))) from++;
    if (this.text.charAt(from) === "<") {
      return this.spanBetween(from + 1, this.text.indexOf(">", from));
    }
    let to = from;
    while (to < end && !/[\s)]/.test(this.text.charAt(to))) to++;
    return this.spanBetween(from, to);
  }

  private offsetOf({ line, column }: Position): number {
    const lineStart = this.lineStarts[line - this.lineOffset - 1];
    if (lineStart === undefined) {
      throw new Error(`Line ${line} is not in the body`);
    }
    return lineStart + column - 1;
  }

  private positionOf(offset: number): Position {
    const index = this.lineStarts.findLastIndex((start) => start <= offset);
    const lineStart = this.lineStarts[index] ?? 0;
    return {
      line: index + 1 + this.lineOffset,
      column: offset - lineStart + 1,
    };
  }

  private spanBetween(start: number, end: number): Span {
    return { start: this.positionOf(start), end: this.positionOf(end) };
  }
}

/** Splits `target#fragment` at the first `#`; the fragment is kept as written. */
function splitFragment(target: string): [string, string | undefined] {
  const hash = target.indexOf("#");
  return hash === -1
    ? [target, undefined]
    : [target.slice(0, hash), target.slice(hash + 1)];
}

function decode(text: string): string | undefined {
  try {
    return decodeURIComponent(text);
  } catch {
    return undefined;
  }
}

function decodeOr(text: string): string {
  return decode(text) ?? text;
}

function indented(lines: string[]): string {
  return lines.map((line) => `    ${line}`).join("\n");
}
