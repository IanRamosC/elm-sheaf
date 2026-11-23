import type { Nodes, Parents } from "mdast";
import { definitions } from "mdast-util-definitions";
import { fromMarkdown } from "mdast-util-from-markdown";
import { gfmFromMarkdown } from "mdast-util-gfm";
import { gfm } from "micromark-extension-gfm";
import type { SourceDocument } from "../content/document";
import type { Diagnostic, Span } from "../diagnostics/diagnostic";
import { err, ok, type Result } from "../result";
import { HeadingIds } from "./heading-id";
import type { Node } from "./tree";

/**
 * Parses a document's body (CommonMark plus GFM tables, task lists,
 * strikethrough, footnotes and autolinks) into the protocol tree. Raw HTML is
 * an error: every occurrence is reported, not just the first.
 */
export function parseMarkdown(
  document: SourceDocument,
): Result<Node, Diagnostic[]> {
  const root = fromMarkdown(document.body, {
    extensions: [gfm()],
    mdastExtensions: [gfmFromMarkdown()],
  });
  const definitionFor = definitions(root);
  const headingIds = new HeadingIds();
  const errors: Diagnostic[] = [];
  const lineOffset = document.bodyStartLine - 1;

  function spanOf(node: Nodes): Span {
    const { start, end } = node.position ?? missingPosition(node);
    return {
      start: { line: start.line + lineOffset, column: start.column },
      end: { line: end.line + lineOffset, column: end.column },
    };
  }

  function convertChildren(node: Parents): Node[] {
    return node.children.flatMap((child) =>
      child.type === "definition" ? [] : convert(child),
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
            identifier: node.identifier,
            children: convertChildren(node),
          },
        ];
      case "footnoteReference":
        return [
          { type: "footnoteReference", position, identifier: node.identifier },
        ];
      case "html":
        errors.push({
          severity: "error",
          title: "RAW HTML",
          message: `This document contains raw HTML (\`${node.value}\`).`,
          sourcePath: document.sourcePath,
          span: position,
          hint: "Raw HTML is not supported. Use a component instead.",
        });
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

function missingPosition(node: Nodes): never {
  throw new Error(`Markdown ${node.type} node has no position`);
}
