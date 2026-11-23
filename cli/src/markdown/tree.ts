import type { Span } from "../diagnostics/diagnostic";

/**
 * The Markdown part of the JSON the host sends to the Elm worker, a subset of
 * mdast. Elm mirrors this union exactly, so a change here is a protocol
 * change. Positions are file-relative (the body's offset is already added).
 */
export type Node = { position: Span } & (
  | { type: "root"; children: Node[] }
  | { type: "paragraph"; children: Node[] }
  | { type: "heading"; depth: number; id: string; children: Node[] }
  | { type: "text"; value: string }
  | { type: "emphasis"; children: Node[] }
  | { type: "strong"; children: Node[] }
  | { type: "delete"; children: Node[] }
  | { type: "inlineCode"; value: string }
  | { type: "code"; lang?: string; value: string }
  | { type: "blockquote"; children: Node[] }
  | {
      type: "list";
      ordered: boolean;
      start?: number;
      spread: boolean;
      children: Node[];
    }
  | { type: "listItem"; checked?: boolean; children: Node[] }
  | { type: "thematicBreak" }
  | { type: "break" }
  | { type: "link"; url: string; title?: string; children: Node[] }
  | {
      type: "sheafLink";
      collection: string;
      slug: string;
      fragment?: string;
      title?: string;
      children: Node[];
    }
  | { type: "image"; url: string; alt: string; title?: string }
  | { type: "table"; align: TableAlignment[]; children: Node[] }
  | { type: "tableRow"; children: Node[] }
  | { type: "tableCell"; children: Node[] }
  | { type: "footnoteDefinition"; identifier: string; children: Node[] }
  | { type: "footnoteReference"; identifier: string }
);

/** How a table column is aligned; `null` when the column has no alignment marker. */
export type TableAlignment = "left" | "right" | "center" | null;
