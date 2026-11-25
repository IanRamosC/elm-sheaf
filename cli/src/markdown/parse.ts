import type { Nodes, Parents } from "mdast";
import { definitions } from "mdast-util-definitions";
import {
  type ContainerDirective,
  directiveFromMarkdown,
  type LeafDirective,
} from "mdast-util-directive";
import { fromMarkdown } from "mdast-util-from-markdown";
import { gfmFromMarkdown } from "mdast-util-gfm";
import { directive } from "micromark-extension-directive";
import { gfm } from "micromark-extension-gfm";
import { normalizeUri } from "micromark-util-sanitize-uri";
import type { SourceDocument } from "../content/document";
import type { Diagnostic, Span } from "../diagnostics/diagnostic";
import { err, ok, type Result } from "../result";
import { HeadingIds } from "./heading-id";
import type { DirectiveAttribute, Node } from "./tree";

type SourcePosition = NonNullable<Nodes["position"]>;
type SourcePoint = SourcePosition["start"];

/**
 * Parses a document's body (CommonMark plus GFM tables, task lists,
 * strikethrough, footnotes and autolinks, and container and leaf directives)
 * into the protocol tree. Raw HTML is an error: every occurrence is reported,
 * not just the first.
 */
export function parseMarkdown(
  document: SourceDocument,
): Result<Node, Diagnostic[]> {
  const root = fromMarkdown(document.body, {
    // Text directives (`:name[…]`) are not part of Sheaf, so their syntax is
    // left out and prose such as `12:30` stays plain CommonMark everywhere,
    // image descriptions and heading ids included.
    extensions: [gfm(), { flow: directive().flow }],
    // `verbose` records where a container's opening and closing fences are.
    mdastExtensions: [
      gfmFromMarkdown(),
      directiveFromMarkdown({ verbose: true }),
    ],
  });
  const definitionFor = definitions(root);
  const headingIds = new HeadingIds();
  const errors: Diagnostic[] = [];
  const lineOffset = document.bodyStartLine - 1;

  function spanOf(node: Nodes): Span {
    return toSpan(node.position ?? missingPosition(node));
  }

  function toSpan({ start, end }: SourcePosition): Span {
    return {
      start: { line: start.line + lineOffset, column: start.column },
      end: { line: end.line + lineOffset, column: end.column },
    };
  }

  function problem(
    title: string,
    span: Span,
    message: string,
    hint?: string,
  ): Diagnostic {
    return {
      severity: "error",
      title,
      message,
      sourcePath: document.sourcePath,
      span,
      ...(hint === undefined ? {} : { hint }),
    };
  }

  function convertChildren(node: Parents): Node[] {
    // Inline HTML arrives one tag at a time, so `<b>bold</b>` is two nodes.
    // The closing tag of an element already reported is not a second problem.
    const reportedTags = new Set<string>();
    return node.children.flatMap((child) => {
      if (child.type === "definition") return [];
      if (child.type === "html") {
        const closing = tagName(CLOSING_TAG, child.value);
        if (closing !== undefined && reportedTags.delete(closing)) return [];
        const opening = tagName(OPENING_TAG, child.value);
        if (opening !== undefined) reportedTags.add(opening);
      }
      return convert(child);
    });
  }

  /**
   * The attributes in the order they are written. `mdast-util-directive` gives
   * them as an object, which loses that order and any repeat, so the names
   * are read again from the source; the values still come from the object,
   * with their character references decoded.
   */
  function attributesOf(
    node: ContainerDirective | LeafDirective,
    position: Span,
  ): DirectiveAttribute[] {
    const values = node.attributes ?? {};
    const { start } = node.position ?? missingPosition(node);
    const attributes: DirectiveAttribute[] = [];
    const repeated = new Set<string>();
    for (const name of attributeNames(document.body, offsetOf(node, start))) {
      if (!attributes.some((attribute) => attribute.name === name)) {
        // Not `values[name]`, which for `__proto__` is the object's prototype.
        const value = Object.hasOwn(values, name) ? values[name] : undefined;
        attributes.push({ name, value: value ?? "" });
      } else if (name !== "class" && !repeated.has(name)) {
        // Classes combine, so only other names can be written twice.
        repeated.add(name);
        errors.push(
          problem(
            "DUPLICATE ATTRIBUTE",
            position,
            `The \`${name}\` attribute is written twice.`,
          ),
        );
      }
    }
    return attributes;
  }

  function reportLabel(position: Span): void {
    errors.push(
      problem(
        "DIRECTIVE LABEL",
        position,
        "Components don't take a `[label]` in this version of Sheaf.",
        'Pass the text as an attribute instead, such as `::youtube{title="My video"}`.',
      ),
    );
  }

  /**
   * A container without a closing fence runs to the end of the document,
   * swallowing everything after it. One that an outer fence closes ends
   * earlier, and is not a problem.
   */
  function checkClosed(node: ContainerDirective): void {
    const fences = node.data?.position;
    const { end } = node.position ?? missingPosition(node);
    if (fences?.closing || offsetOf(node, end) < document.body.length) return;
    errors.push(
      problem(
        "UNCLOSED COMPONENT",
        toSpan(fences?.opening ?? missingPosition(node)),
        `The \`${node.name}\` component is never closed, so it would take in the rest of the document.`,
        "Close it with a line holding only `:::`.",
      ),
    );
  }

  // Returns a list because raw HTML converts to nothing (it is reported instead).
  function convert(node: Nodes): Node[] {
    const position = spanOf(node);
    switch (node.type) {
      case "root":
      case "paragraph":
      case "emphasis":
      case "strong":
      case "delete":
      case "blockquote":
      case "tableRow":
      case "tableCell":
        return [{ type: node.type, position, children: convertChildren(node) }];
      case "heading":
        return [
          {
            type: "heading",
            position,
            depth: node.depth,
            id: headingIds.next(plainText(node)),
            children: convertChildren(node),
          },
        ];
      case "text":
      case "inlineCode":
        return [{ type: node.type, position, value: node.value }];
      case "code":
        return [
          {
            type: "code",
            position,
            ...(node.lang ? { lang: node.lang } : {}),
            value: node.value,
          },
        ];
      case "list":
        return [
          {
            type: "list",
            position,
            ordered: node.ordered ?? false,
            ...(node.start != null ? { start: node.start } : {}),
            spread: node.spread ?? false,
            children: convertChildren(node),
          },
        ];
      case "listItem":
        return [
          {
            type: "listItem",
            position,
            ...(node.checked != null ? { checked: node.checked } : {}),
            children: convertChildren(node),
          },
        ];
      case "thematicBreak":
      case "break":
        return [{ type: node.type, position }];
      case "link":
        return [
          {
            type: "link",
            position,
            url: node.url,
            ...(node.title ? { title: node.title } : {}),
            children: convertChildren(node),
          },
        ];
      case "linkReference": {
        const definition = resolve(node.identifier);
        return [
          {
            type: "link",
            position,
            url: definition.url,
            ...(definition.title ? { title: definition.title } : {}),
            children: convertChildren(node),
          },
        ];
      }
      case "image":
        return [
          {
            type: "image",
            position,
            url: node.url,
            alt: node.alt ?? "",
            ...(node.title ? { title: node.title } : {}),
          },
        ];
      case "imageReference": {
        const definition = resolve(node.identifier);
        return [
          {
            type: "image",
            position,
            url: definition.url,
            alt: node.alt ?? "",
            ...(definition.title ? { title: definition.title } : {}),
          },
        ];
      }
      case "table":
        return [
          {
            type: "table",
            position,
            align: node.align ?? [],
            children: convertChildren(node),
          },
        ];
      case "footnoteDefinition":
        return [
          {
            type: "footnoteDefinition",
            position,
            identifier: footnoteId(node.identifier),
            children: convertChildren(node),
          },
        ];
      case "footnoteReference":
        return [
          {
            type: "footnoteReference",
            position,
            identifier: footnoteId(node.identifier),
          },
        ];
      case "containerDirective": {
        const [first] = node.children;
        if (first?.type === "paragraph" && first.data?.directiveLabel) {
          reportLabel(position);
        }
        checkClosed(node);
        return [
          {
            type: "containerDirective",
            position,
            name: node.name,
            attributes: attributesOf(node, position),
            children: convertChildren(node),
          },
        ];
      }
      case "leafDirective":
        if (node.children.length > 0) reportLabel(position);
        return [
          {
            type: "leafDirective",
            position,
            name: node.name,
            attributes: attributesOf(node, position),
          },
        ];
      case "html":
        errors.push(
          problem(
            "RAW HTML",
            position,
            `This document contains raw HTML (\`${firstLine(node.value)}\`).`,
            "Raw HTML is not supported. Use a component instead.",
          ),
        );
        return [];
      default:
        throw new Error(`Unsupported Markdown node type: ${node.type}`);
    }
  }

  // mdast only creates a reference node when its definition exists.
  function resolve(identifier: string) {
    const definition = definitionFor(identifier);
    if (!definition) {
      throw new Error(`Reference \`${identifier}\` has no definition`);
    }
    return definition;
  }

  const [tree] = convert(root);
  if (errors.length > 0 || !tree) return err(errors);
  return ok(tree);
}

/** The text of a heading with emphasis and other markup stripped. */
function plainText(node: Nodes): string {
  if (node.type === "text" || node.type === "inlineCode") return node.value;
  return "children" in node ? node.children.map(plainText).join("") : "";
}

/**
 * Footnote identifiers become `id`s and `#` links, so they are made URL-safe
 * the way `mdast-util-to-hast` does. `normalizeUri` keeps existing escapes,
 * so `[^é]` and `[^%C3%A9]` are the same footnote, as on GitHub.
 */
function footnoteId(identifier: string): string {
  return normalizeUri(identifier.toLowerCase());
}

function missingPosition(node: Nodes): never {
  throw new Error(`Markdown ${node.type} node has no position`);
}

function offsetOf(node: Nodes, point: SourcePoint): number {
  if (point.offset === undefined) {
    throw new Error(`Markdown ${node.type} node has no offset`);
  }
  return point.offset;
}

// One attribute inside `{…}`: an `#id` or `.class` shortcut, or a name with an
// optional value, as `micromark-extension-directive` reads it.
const ATTRIBUTE =
  /\s*(?:([#.])[^\s#.}]*|([^\s=}]+)(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s}]+))?)/y;

/**
 * The attribute names of the directive whose `:` marker is at `start`, in
 * the order they are written, repeats included. micromark has already
 * checked the syntax, so this only steps over the name and the label.
 */
function attributeNames(source: string, start: number): string[] {
  let at = start;
  while (source[at] === ":") at++;
  while (at < source.length && !/[\s[{]/.test(source.charAt(at))) at++;
  if (source[at] === "[") at = labelEnd(source, at);
  if (source[at] !== "{") return [];

  const names: string[] = [];
  ATTRIBUTE.lastIndex = at + 1;
  for (
    let match = ATTRIBUTE.exec(source);
    match !== null;
    match = ATTRIBUTE.exec(source)
  ) {
    const [, shortcut, name] = match;
    if (shortcut === "#") names.push("id");
    else if (shortcut === ".") names.push("class");
    else if (name !== undefined) names.push(name);
  }
  return names;
}

/** Just after the `]` that closes the label opened at `open`. */
function labelEnd(source: string, open: number): number {
  let depth = 0;
  for (let at = open + 1; at < source.length; at++) {
    const character = source[at];
    if (character === "\\") at++;
    else if (character === "[") depth++;
    else if (character === "]" && depth-- === 0) return at + 1;
  }
  return source.length;
}

const OPENING_TAG = /^<([A-Za-z][A-Za-z0-9-]*)\b[^>]*>$/;
const CLOSING_TAG = /^<\/([A-Za-z][A-Za-z0-9-]*)\s*>$/;

function tagName(pattern: RegExp, html: string): string | undefined {
  return pattern.exec(html)?.[1]?.toLowerCase();
}

/** A block of HTML can run for many lines; its first is enough to find it. */
function firstLine(text: string): string {
  const [first = "", ...rest] = text.split("\n");
  return rest.length > 0 ? `${first}…` : first;
}
