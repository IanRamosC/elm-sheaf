/** A 1-based line and column in a source file. */
export type Position = { line: number; column: number };

/**
 * A region of a source file. `end` is exclusive (the column after the last
 * character), the same convention as mdast, so parser positions are used as-is.
 */
export type Span = { start: Position; end: Position };

/** A problem found while building a site, with enough context to point at its cause. */
export type Diagnostic = {
  severity: "error" | "warning";
  title: string;
  message: string;
  sourcePath?: string;
  span?: Span;
  /**
   * `false` when the message already quotes the source, as the Elm
   * compiler's messages do, so the renderer adds no excerpt of its own.
   */
  excerpt?: false;
  hint?: string;
};
