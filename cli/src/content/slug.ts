import type { SourceDocument } from "./document";

/**
 * Case-folds `value` and drops Latin accents, so that spellings a reader
 * would call the same compare equal.
 *
 * Only the Combining Diacritical Marks block is removed: stripping every
 * mark would also destroy Japanese voicing marks (`ばか` against `はか`) and
 * Devanagari or Hangul vowel signs, which are part of the letters. The
 * result is recomposed so such text stays in its usual form.
 *
 * `toLowerCase` is not case folding, so the two cases that matter are mapped
 * by hand: Greek final sigma (`ΟΔΟΣ` lowercases to `οδος`, which would
 * differ from `οδοσ`) and `ß`. Without this, two spellings could become two
 * folders that collide on a case-insensitive disk.
 */
function foldCase(value: string): string {
  return value
    .normalize("NFKD")
    .replace(/[̀-ͯ]/g, "")
    .normalize("NFC")
    .toLowerCase()
    .replace(/ς/g, "σ")
    .replace(/ß/g, "ss");
}

/**
 * The URL segment for a frontmatter value: `Tiếng Việt` becomes
 * `tieng-viet`. Letters, marks and digits of any script are kept; every
 * other run of characters becomes one `-`. It is `""` when nothing
 * survives, as for `+++`.
 */
export function slugOf(value: string): string {
  return foldCase(value)
    .replace(/[^\p{L}\p{M}\p{N}]+/gu, "-")
    .replace(/^-+|-+$/g, "");
}

/**
 * The key under which spellings of a value are treated as one group:
 * `Élm` and `elm` match, as do `open source`, `open-source` and
 * `open_source`. Other punctuation is kept, because `c` and `c++` are
 * different tags that merely share a slug.
 */
export function foldOf(value: string): string {
  return foldCase(value)
    .replace(/[\s_-]+/gu, " ")
    .trim();
}

/** A frontmatter string with the slug and fold that Elm groups it by. */
export type GroupSlug = { value: string; slug: string; folded: string };

function collectStrings(value: unknown, found: Set<string>): void {
  if (typeof value === "string") {
    found.add(value);
  } else if (Array.isArray(value)) {
    for (const item of value) {
      collectStrings(item, found);
    }
  } else if (typeof value === "object" && value !== null) {
    for (const item of Object.values(value)) {
      collectStrings(item, found);
    }
  }
}

/**
 * One entry for every distinct string anywhere in the documents'
 * frontmatter, in first-seen order. It is a list rather than an object
 * keyed by value because `elm/json`'s `Decode.dict` crashes on a key such as
 * `hasOwnProperty`.
 */
export function slugTable(documents: SourceDocument[]): GroupSlug[] {
  const values = new Set<string>();
  for (const document of documents) {
    collectStrings(document.frontmatter, values);
  }
  return [...values].map((value) => ({
    value,
    slug: slugOf(value),
    folded: foldOf(value),
  }));
}
