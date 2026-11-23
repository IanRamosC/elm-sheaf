/**
 * Turns heading text into GitHub-style anchor ids: lowercase, punctuation
 * removed, spaces become hyphens. A repeated heading gets `-1`, `-2`, ...
 * so every id in a document is unique.
 */
export class HeadingIds {
  private readonly issued = new Set<string>();
  private readonly repeats = new Map<string, number>();

  /** The id for the next heading in the document, whose plain text is `text`. */
  next(text: string): string {
    const base = text
      .toLowerCase()
      .replace(/[^\p{L}\p{M}\p{N}\p{Pc} -]/gu, "")
      .replace(/ /g, "-");
    let id = base;
    let count = this.repeats.get(base) ?? 0;
    while (this.issued.has(id)) {
      count += 1;
      id = `${base}-${count}`;
    }
    this.repeats.set(base, count);
    this.issued.add(id);
    return id;
  }
}
