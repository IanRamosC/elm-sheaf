import type { SourceDocument } from "../content/document";
import type { Diagnostic } from "../diagnostics/diagnostic";
import { err, ok, type Result } from "../result";

// Two names are not keywords but still unusable: every generated collection
// module defines `all`, and Elm requires any top-level `main` to be a program.
const RESERVED_VALUE_NAMES = new Set([
  "all",
  "main",
  "if",
  "then",
  "else",
  "case",
  "of",
  "let",
  "in",
  "type",
  "module",
  "where",
  "import",
  "exposing",
  "as",
  "port",
  "alias",
  "infix",
]);

/**
 * The letter and digit runs of `text`. Accents are folded to their base
 * letters first, so `café` stays readable; characters with no ASCII form
 * (such as CJK) are dropped.
 */
function wordsOf(text: string): string[] {
  return text
    .normalize("NFKD")
    .replace(/\p{M}/gu, "")
    .split(/[^A-Za-z0-9]+/)
    .filter((word) => word !== "");
}

function capitalise(word: string): string {
  return word.charAt(0).toUpperCase() + word.slice(1);
}

/** The generated Elm module name for a collection: `release-notes` becomes `ReleaseNotes`. */
export function elmModuleName(collection: string): Result<string, string> {
  const words = wordsOf(collection);
  if (words.length === 0) {
    return err(
      `"${collection}" has no letters or digits to build an Elm module name from`,
    );
  }
  return ok(words.map(capitalise).join(""));
}

/**
 * The generated Elm value name for a slug: `hello-world` becomes `helloWorld`.
 * A leading digit gets an `n` prefix and an Elm keyword (or `all`, or `main`) a `_` suffix, because
 * neither is a legal value name as written.
 */
export function elmValueName(slug: string): Result<string, string> {
  const [first, ...rest] = wordsOf(slug);
  if (first === undefined) {
    return err(
      `"${slug}" has no letters or digits to build an Elm value name from`,
    );
  }
  const name = first.toLowerCase() + rest.map(capitalise).join("");
  if (/^[0-9]/.test(name)) {
    return ok(`n${name}`);
  }
  return ok(RESERVED_VALUE_NAMES.has(name) ? `${name}_` : name);
}

function unusableSlug(document: SourceDocument, reason: string): Diagnostic {
  return {
    severity: "error",
    title: "UNUSABLE SLUG",
    message: reason,
    sourcePath: document.sourcePath,
    hint: "Set `slug` in the frontmatter to a name with ASCII letters or digits.",
  };
}

/** `documents` starts with `first`; the diagnostic points at that file. */
function nameClash(
  name: string,
  first: SourceDocument,
  documents: SourceDocument[],
): Diagnostic {
  const files = documents.map((document) => document.sourcePath).join(", ");
  return {
    severity: "error",
    title: "NAME CLASH",
    message: `In "${first.collection}", ${files} all become \`${name}\`.`,
    sourcePath: first.sourcePath,
    hint: "Give one of them a different `slug` in its frontmatter.",
  };
}

/**
 * Names every document's generated Elm value, keyed by document id. Names are
 * only unique within a collection, since each collection is its own module.
 * Every unusable slug and every clash is reported, not just the first.
 */
export function assignValueNames(
  documents: SourceDocument[],
): Result<Map<string, string>, Diagnostic[]> {
  const names = new Map<string, string>();
  const diagnostics: Diagnostic[] = [];
  const claimants = new Map<string, SourceDocument[]>();

  for (const document of documents) {
    const name = elmValueName(document.slug);
    if (!name.ok) {
      diagnostics.push(unusableSlug(document, name.error));
      continue;
    }
    names.set(document.id, name.value);
    const key = `${document.collection}/${name.value}`;
    claimants.set(key, [...(claimants.get(key) ?? []), document]);
  }

  for (const sharing of claimants.values()) {
    const [first] = sharing;
    if (first !== undefined && sharing.length > 1) {
      diagnostics.push(nameClash(names.get(first.id) ?? "", first, sharing));
    }
  }

  return diagnostics.length > 0 ? err(diagnostics) : ok(names);
}
