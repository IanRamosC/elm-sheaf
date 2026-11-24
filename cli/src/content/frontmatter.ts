import {
  isMap,
  isScalar,
  isSeq,
  LineCounter,
  type Node,
  parseDocument,
} from "yaml";
import type { Diagnostic, Position, Span } from "../diagnostics/diagnostic";
import { err, ok, type Result } from "../result";

/**
 * Where a frontmatter value sits in its file. `key` is absent for list items,
 * which have no key; an error about a value underlines `value`, and one about
 * a key (an unknown field, say) underlines `key`.
 */
export type FieldPosition = { key?: Span; value: Span };

/** A Markdown file taken apart into its frontmatter and body. */
export type SplitSource = {
  data: Record<string, unknown>;
  /**
   * Keyed by dotted path (`tags`, `tags.1`, `author.name`), in file lines and
   * columns. The root path `""` is always present so that a missing field
   * still has somewhere to point: the opening fence, or an empty span at 1:1
   * when the file has no frontmatter, which Elm mentions in its hint.
   */
  positions: Record<string, FieldPosition>;
  body: string;
  /** The 1-based file line on which `body` begins. */
  bodyStartLine: number;
};

const FENCE = "---";
const LEADING_BYTE_ORDER_MARK = /^\uFEFF/;

/**
 * Splits `---`-fenced YAML frontmatter from the Markdown that follows it. A
 * file that does not open with a fence has no frontmatter.
 */
export function splitFrontmatter(
  source: string,
  sourcePath: string,
): Result<SplitSource, Diagnostic[]> {
  // Positions are the same for LF and CRLF files because the line endings are
  // normalised here; the body is returned with LF endings for the same reason.
  const lines = source
    .replace(LEADING_BYTE_ORDER_MARK, "")
    .replaceAll("\r\n", "\n")
    .split("\n");
  const isFence = (line: string) => line.trimEnd() === FENCE;

  if (!isFence(lines[0] ?? "")) {
    return ok({
      data: {},
      positions: { "": { value: span(1, 1, 1, 1) } },
      body: lines.join("\n"),
      bodyStartLine: 1,
    });
  }

  const openingFence = span(1, 1, 1, FENCE.length + 1);
  const closingIndex = lines.findIndex(
    (line, index) => index > 0 && isFence(line),
  );
  if (closingIndex === -1) {
    return err([
      badFrontmatter(
        sourcePath,
        "This file opens frontmatter with `---` but never closes it.",
        openingFence,
        "Add a line containing only `---` after the last frontmatter field.",
      ),
    ]);
  }

  const yaml = lines.slice(1, closingIndex).join("\n");
  const parsed = parseYaml(yaml, sourcePath);
  if (!parsed.ok) return parsed;

  return ok({
    data: parsed.value.data,
    positions: { ...parsed.value.positions, "": { value: openingFence } },
    body: lines.slice(closingIndex + 1).join("\n"),
    bodyStartLine: closingIndex + 2,
  });
}

type ParsedYaml = Pick<SplitSource, "data" | "positions">;

// The YAML sits below the opening fence, so its line 1 is file line 2.
const YAML_FIRST_FILE_LINE = 2;

function parseYaml(
  yaml: string,
  sourcePath: string,
): Result<ParsedYaml, Diagnostic[]> {
  const lineCounter = new LineCounter();
  const document = parseDocument(yaml, { lineCounter, prettyErrors: false });

  const fileSpan = (start: number, end: number): Span => {
    const from = filePosition(lineCounter.linePos(start));
    const to = filePosition(lineCounter.linePos(end));
    return { start: from, end: to };
  };

  if (document.errors.length > 0) {
    return err(
      document.errors.map((error) =>
        badFrontmatter(sourcePath, error.message, fileSpan(...error.pos)),
      ),
    );
  }

  const root = document.contents;
  if (root === null) return ok({ data: {}, positions: {} });
  if (!isMap(root)) {
    const [start, end] = root.range ?? [0, 0];
    return err([
      badFrontmatter(
        sourcePath,
        "Frontmatter must be a list of `key: value` fields.",
        fileSpan(start, end),
      ),
    ]);
  }

  const positions: Record<string, FieldPosition> = {};
  const record = (path: string, key: Node | null, value: Node | null) => {
    if (value?.range) {
      positions[path] = {
        ...(key?.range && { key: fileSpan(key.range[0], key.range[1]) }),
        value: fileSpan(value.range[0], value.range[1]),
      };
    }
  };
  const walk = (node: unknown, path: string) => {
    if (isMap(node)) {
      for (const pair of node.items) {
        if (!isScalar(pair.key)) continue;
        const childPath = joinPath(path, String(pair.key.value));
        record(childPath, pair.key, pair.value as Node | null);
        walk(pair.value, childPath);
      }
    } else if (isSeq(node)) {
      node.items.forEach((item, index) => {
        const childPath = joinPath(path, String(index));
        record(childPath, null, item as Node | null);
        walk(item, childPath);
      });
    }
  };
  walk(root, "");

  return ok({ data: document.toJS() as Record<string, unknown>, positions });
}

function filePosition({ line, col }: { line: number; col: number }): Position {
  return { line: line + YAML_FIRST_FILE_LINE - 1, column: col };
}

function joinPath(parent: string, child: string): string {
  return parent === "" ? child : `${parent}.${child}`;
}

function span(
  startLine: number,
  startColumn: number,
  endLine: number,
  endColumn: number,
): Span {
  return {
    start: { line: startLine, column: startColumn },
    end: { line: endLine, column: endColumn },
  };
}

function badFrontmatter(
  sourcePath: string,
  message: string,
  at: Span,
  hint?: string,
): Diagnostic {
  return {
    severity: "error",
    title: "BAD FRONTMATTER",
    message,
    sourcePath,
    span: at,
    ...(hint === undefined ? {} : { hint }),
  };
}
