import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { extname } from "node:path";
import type { OutputFile } from "./write";

/** A stylesheet of `static/` and the copy of it named by its contents, both relative to `dist/`. */
export type Stylesheet = { path: string; hashed: string };

const HASH_LENGTH = 8;

/**
 * Names a file by its contents: the first eight hex digits of their SHA-256
 * go before the extension, in the same folder, so `css/style.css` becomes
 * `css/style.3f2a9c1e.css`. Paths are relative to `dist/`.
 */
export function hashedPath(path: string, bytes: Uint8Array): string {
  const hash = createHash("sha256")
    .update(bytes)
    .digest("hex")
    .slice(0, HASH_LENGTH);
  const extension = extname(path);
  return `${path.slice(0, path.length - extension.length)}.${hash}${extension}`;
}

/**
 * The stylesheets among the files of `static/`, and a copy of each under its
 * hashed name, so a page can link a name that changes with the contents and
 * be cached for as long as a server allows. The original stays where it is.
 */
export async function stylesheetCopies(
  staticFiles: OutputFile[],
): Promise<{ stylesheets: Stylesheet[]; copies: OutputFile[] }> {
  const stylesheets: Stylesheet[] = [];
  const copies: OutputFile[] = [];
  for (const file of staticFiles) {
    if (file.kind !== "copy" || extname(file.path).toLowerCase() !== ".css") {
      continue;
    }
    const hashed = hashedPath(file.path, await readFile(file.source));
    stylesheets.push({ path: file.path, hashed });
    copies.push({ kind: "copy", path: hashed, source: file.source });
  }
  return { stylesheets, copies };
}
