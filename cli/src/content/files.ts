import { readdir } from "node:fs/promises";
import { join, relative, sep } from "node:path";

/** What a lookup in {@link ContentFiles} found. */
export type FileLookup =
  | { found: string }
  /** The only file with this path differs from it in case. */
  | { caseOf: string };

/**
 * Every file under `content/`, so links and images are looked up the same way
 * on every machine. macOS stores names in NFD and ignores case, while Linux
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
}

/**
 * Lists every file under `<root>/content`, skipping hidden files and folders
 * (`.obsidian`, `.git`), which belong to other tools.
 */
export async function listContentFiles(root: string): Promise<ContentFiles> {
  let entries: Awaited<ReturnType<typeof readEntries>>;
  try {
    entries = await readEntries(join(root, "content"));
  } catch (error) {
    // A site without `content/` has no files; `readContentFiles` agrees.
    if ((error as NodeJS.ErrnoException).code === "ENOENT") {
      return new ContentFiles([]);
    }
    throw error;
  }
  const paths = entries
    .filter((entry) => entry.isFile())
    .map((entry) =>
      relative(root, join(entry.parentPath, entry.name)).split(sep).join("/"),
    )
    .filter((path) => !path.split("/").some((name) => name.startsWith(".")));
  return new ContentFiles(paths);
}

function readEntries(folder: string) {
  return readdir(folder, { recursive: true, withFileTypes: true });
}
