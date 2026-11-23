import type { Diagnostic, Span } from "./diagnostic";

const HEADER_WIDTH = 80;
const MIN_RULE = 4;
const LINE_NUMBER_WIDTH = 5;

/**
 * Formats a diagnostic as plain text: a titled header, the message, the
 * offending source line underlined with carets, and an optional hint.
 * Colour is added by the CLI, so this stays free of escape codes.
 */
export function renderDiagnostic(
  diagnostic: Diagnostic,
  source: string | undefined,
): string {
  const sections = [renderHeader(diagnostic), diagnostic.message];

  const excerpt =
    diagnostic.span && diagnostic.excerpt !== false && source !== undefined
      ? renderExcerpt(diagnostic.span, source)
      : undefined;
  if (excerpt) {
    sections.push(excerpt);
  }
  if (diagnostic.hint) {
    sections.push(diagnostic.hint);
  }
  return sections.join("\n\n");
}

function renderHeader({ title, sourcePath, span }: Diagnostic): string {
  const left = `-- ${title} `;
  if (sourcePath === undefined) {
    return left.padEnd(HEADER_WIDTH, "-");
  }
  const location = span
    ? `${sourcePath}:${span.start.line}:${span.start.column}`
    : sourcePath;
  const rule = "-".repeat(
    Math.max(MIN_RULE, HEADER_WIDTH - left.length - location.length - 1),
  );
  return `${left}${rule} ${location}`;
}

function renderExcerpt(span: Span, source: string): string | undefined {
  const line = source.split(/\r?\n/)[span.start.line - 1];
  if (line === undefined) {
    return undefined;
  }
  const gutter = `${String(span.start.line).padStart(LINE_NUMBER_WIDTH)}| `;
  // A span running onto later lines is underlined to the end of its first line.
  const endColumn =
    span.end.line === span.start.line ? span.end.column : line.length + 1;
  const caretCount = Math.max(1, endColumn - span.start.column);
  const underline =
    " ".repeat(gutter.length + span.start.column - 1) + "^".repeat(caretCount);
  return `${gutter}${line}\n${underline}`;
}
