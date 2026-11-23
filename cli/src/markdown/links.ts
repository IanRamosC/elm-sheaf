import { posix } from "node:path";
import type { SourceDocument } from "../content/document";
import type { Diagnostic } from "../diagnostics/diagnostic";
import { collect, err, ok, type Result } from "../result";
import { suggestions } from "../suggest";
import { URL_SCHEMES } from "../url-schemes";
import type { Node } from "./tree";

type Link = Extract<Node, { type: "link" }>;

const MAX_SUGGESTIONS = 3;
const SCHEME_PREFIX = /^([A-Za-z][A-Za-z0-9+.-]*):/;

/**
 * Checks every Markdown link that points at another document, either as
 * `<collection>:<slug>[#fragment]` or as a relative path to its `.md` file,
 * and rewrites it into a `sheafLink`. Other links are left as they are.
 * Every broken link is reported, not just the first.
 */
export function checkLinks(
  tree: Node,
  document: SourceDocument,
  all: SourceDocument[],
): Result<Node, Diagnostic[]> {
  const bySourcePath = new Map(all.map((other) => [other.sourcePath, other]));
  const slugsByCollection = new Map<string, string[]>();
  for (const { collection, slug } of all) {
    slugsByCollection.set(collection, [
      ...(slugsByCollection.get(collection) ?? []),
      slug,
    ]);
  }

  function broken(link: Link, message: string, hint?: string): Diagnostic {
    return {
      severity: "error",
      title: "BROKEN LINK",
      message,
      sourcePath: document.sourcePath,
      span: link.position,
      ...(hint === undefined ? {} : { hint }),
    };
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
    target: string,
  ): Result<Node, Diagnostic[]> {
    const [encodedPath = "", fragment] = splitFragment(target);
    const path = decode(encodedPath);
    if (path === undefined) {
      return err([
        broken(
          link,
          `This document links to \`${decodeOr(encodedPath)}\`, which is not validly percent-encoded.`,
        ),
      ]);
    }
    const linked = bySourcePath.get(
      posix.join(posix.dirname(document.sourcePath), path),
    );
    if (!linked) {
      return err([
        broken(
          link,
          `This document links to \`${path}\`, but no such document exists.`,
        ),
      ]);
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
    const [path = ""] = splitFragment(link.url);
    return path.endsWith(".md") ? checkPathLink(link, link.url) : ok(link);
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
