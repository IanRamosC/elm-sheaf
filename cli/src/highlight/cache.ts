import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { join } from "node:path";
import type { Highlight, HighlightToken } from "../markdown/tree";

const CACHE_FOLDER = ".sheaf/cache";
const CACHE_FILE = "highlight.json";

/**
 * Highlighted code from earlier builds, by key. Only the entries a build asks
 * for are saved again, so the file never outgrows the site's code blocks.
 */
export class HighlightCache {
  hits = 0;
  misses = 0;
  readonly #stored: ReadonlyMap<string, Highlight>;
  readonly #used = new Map<string, Highlight>();

  constructor(stored: ReadonlyMap<string, Highlight> = new Map()) {
    this.#stored = stored;
  }

  /** The highlight stored under `key`, or the one `highlight` makes, which is then stored. */
  get(key: string, highlight: () => Highlight): Highlight {
    const cached = this.#used.get(key) ?? this.#stored.get(key);
    if (cached !== undefined) {
      this.hits++;
      this.#used.set(key, cached);
      return cached;
    }
    this.misses++;
    const made = highlight();
    this.#used.set(key, made);
    return made;
  }

  /** The entries this build asked for, which are all a save keeps. */
  used(): ReadonlyMap<string, Highlight> {
    return this.#used;
  }
}

/**
 * Reads `.sheaf/cache/highlight.json`. A missing or unreadable file is an
 * empty cache and a malformed entry is left out: either costs a re-highlight,
 * never a wrong page.
 */
export async function loadHighlightCache(
  siteRoot: string,
): Promise<HighlightCache> {
  let parsed: unknown;
  try {
    parsed = JSON.parse(
      await readFile(join(siteRoot, CACHE_FOLDER, CACHE_FILE), "utf8"),
    );
  } catch {
    return new HighlightCache();
  }
  if (!isRecord(parsed)) return new HighlightCache();
  const entries = new Map<string, Highlight>();
  for (const [key, value] of Object.entries(parsed)) {
    if (isHighlight(value)) entries.set(key, value);
  }
  return new HighlightCache(entries);
}

/**
 * Writes the entries this build used. The file is written under another name
 * and renamed into place, so an interrupted build never leaves half a cache.
 */
export async function saveHighlightCache(
  siteRoot: string,
  cache: HighlightCache,
): Promise<void> {
  const folder = join(siteRoot, CACHE_FOLDER);
  await mkdir(folder, { recursive: true });
  const temporary = join(folder, `${CACHE_FILE}.${crypto.randomUUID()}.tmp`);
  await writeFile(temporary, JSON.stringify(Object.fromEntries(cache.used())));
  await rename(temporary, join(folder, CACHE_FILE));
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isHighlight(value: unknown): value is Highlight {
  return (
    isRecord(value) &&
    typeof value.style === "string" &&
    Array.isArray(value.lines) &&
    value.lines.every(
      (line: unknown) => Array.isArray(line) && line.every(isToken),
    )
  );
}

function isToken(value: unknown): value is HighlightToken {
  return (
    isRecord(value) &&
    typeof value.content === "string" &&
    typeof value.style === "string"
  );
}
