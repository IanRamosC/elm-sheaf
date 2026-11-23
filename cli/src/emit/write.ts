import { cp, mkdir, rm, writeFile } from "node:fs/promises";
import { dirname, join, posix } from "node:path";
import type { Response } from "../elm/protocol";

/**
 * Replaces `.sheaf/gen/` with the generated Elm sources. Deleting the old ones
 * matters: after a collection folder is renamed, a leftover module would keep
 * compiling for templates that still import it.
 */
export async function writeGenerated(
  siteRoot: string,
  files: Map<string, string>,
): Promise<void> {
  const generated = join(siteRoot, ".sheaf/gen");
  for (const path of files.keys()) assertInside(generated, path);
  await rm(generated, { recursive: true, force: true });
  for (const [path, content] of files) {
    await writeInside(generated, path, content);
  }
}

/**
 * Replaces `dist/` with the rendered pages, then copies `static/` into it
 * untouched. Page paths are relative to `dist/`; the base path is the web
 * server's business, so it is never a folder here.
 */
export async function writeSite(
  siteRoot: string,
  pages: Response["pages"],
): Promise<void> {
  const dist = join(siteRoot, "dist");
  // Checked up front so a bad path cannot leave a half-written dist/.
  for (const { path } of pages) assertInside(dist, path);
  await rm(dist, { recursive: true, force: true });
  await mkdir(dist, { recursive: true });
  for (const { path, html } of pages) {
    await writeInside(dist, path, html);
  }
  await cp(join(siteRoot, "static"), dist, {
    recursive: true,
    force: true,
    // Dereferencing keeps a symlinked asset a real file in `dist/`.
    dereference: true,
  }).catch((error: NodeJS.ErrnoException) => {
    if (error.code !== "ENOENT") throw error;
  });
}

/**
 * Elm chooses these paths, and slugs that could escape were rejected while
 * loading, so one that does is a bug worth stopping for.
 */
function assertInside(directory: string, path: string): void {
  if (posix.isAbsolute(path) || path.split("/").includes("..")) {
    throw new Error(`Refusing to write outside ${directory}: ${path}`);
  }
}

async function writeInside(
  directory: string,
  path: string,
  content: string,
): Promise<void> {
  const target = join(directory, path);
  await mkdir(dirname(target), { recursive: true });
  await writeFile(target, content);
}
