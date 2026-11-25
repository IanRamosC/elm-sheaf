import { readdir } from "node:fs/promises";
import { join, relative, sep } from "node:path";

/** What a lookup in {@link ContentFiles} found. */
export type FileLookup =
  | { found: string }
  /** The only file with this path differs from it in case. */
  | { caseOf: string };

/**
 * Every file in some folders of a site, so links and images are looked up
 * the same way on every machine. macOS stores names in NFD and ignores case, while Linux
 * compares bytes exactly, so asking the disk would accept a link on a laptop
 * that breaks the build in CI. Here both sides are NFC-normalised and compared
 * exactly, and a match that ignores case is reported instead of accepted.
 */
export class ContentFiles {
  private readonly byPath = new Map<string, string>();
  private readonly byLowerCasePath = new Map<string, string>();

  /** `paths` are relative to the site root, with `/` separators, as stored on disk. */
  constructor(paths: string[]) {
    for (const path of paths) {
      const normalized = path.normalize("NFC");
      this.byPath.set(normalized, path);
      this.byLowerCasePath.set(normalized.toLowerCase(), path);
    }
  }

  /** Finds the file at `path` (relative to the site root), giving its path as stored on disk. */
  find(path: string): FileLookup | undefined {
    const normalized = path.normalize("NFC");
    const found = this.byPath.get(normalized);
    if (found !== undefined) return { found };
    const caseOf = this.byLowerCasePath.get(normalized.toLowerCase());
    return caseOf === undefined ? undefined : { caseOf };
  }

  /** The names of the files directly in `folder` (relative to the site root), as stored on disk. */
  namesIn(folder: string): string[] {
    const prefix = `${folder.normalize("NFC")}/`;
    return [...this.byPath]
      .filter(
        ([normalized]) =>
          normalized.startsWith(prefix) &&
          !normalized.slice(prefix.length).includes("/"),
      )
      .map(([, stored]) => stored.slice(prefix.length));
  }
}

/** Lists every file under `<root>/content`; see {@link listFiles}. */
export function listContentFiles(root: string): Promise<ContentFiles> {
  return listFiles(root, "content");
}

/**
 * Lists every file under the given folders of `root`, skipping hidden files
 * and folders (`.obsidian`, `.git`), which belong to other tools. A missing
 * folder has no files; `readContentFiles` agrees for `content/`.
 */
export async function listFiles(
  root: string,
  ...folders: string[]
): Promise<ContentFiles> {
  const paths: string[] = [];
  for (const folder of folders) {
    for (const entry of await readEntries(join(root, folder))) {
      if (!entry.isFile()) continue;
      const path = relative(root, join(entry.parentPath, entry.name))
        .split(sep)
        .join("/");
      if (!path.split("/").some((name) => name.startsWith("."))) {
        paths.push(path);
      }
    }
  }
  return new ContentFiles(paths);
}

async function readEntries(folder: string) {
  try {
    return await readdir(folder, { recursive: true, withFileTypes: true });
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return [];
    throw error;
  }
}
