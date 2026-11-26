import { copyFile, mkdir, rm, writeFile } from "node:fs/promises";
import { dirname, join, posix } from "node:path";

/**
 * A file to write to the output folder, with a path relative to it: either text, or
 * a copy of a file elsewhere on disk, such as a cached image. A redirect page
 * has `aliasOf`, the source path of the document it redirects to.
 */
export type OutputFile =
  | { kind: "text"; path: string; content: string; aliasOf?: string }
  | { kind: "copy"; path: string; source: string };

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
 * Replaces `folder` with the rendered pages, feeds and images, then copies the
 * files of `static/` (from `listStaticFiles`) over them. Paths are relative
 * to `folder`; the base path is the web server's business, so it is never a
 * folder here.
 */
export async function writeSite(
  folder: string,
  files: OutputFile[],
  staticFiles: OutputFile[],
): Promise<void> {
  // Checked up front so a bad path cannot leave a half-written folder.
  for (const { path } of [...files, ...staticFiles]) assertInside(folder, path);
  assertNoClashes([...files, ...staticFiles].map(({ path }) => path));
  await rm(folder, { recursive: true, force: true });
  await mkdir(folder, { recursive: true });
  for (const file of [...files, ...staticFiles]) {
    const target = join(folder, file.path);
    await mkdir(dirname(target), { recursive: true });
    if (file.kind === "text") {
      await writeFile(target, file.content);
    } else {
      await copyFile(file.source, target);
    }
  }
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

/**
 * Elm reports clashing outputs as DUPLICATE PAGE and `staticClashes` the
 * static files that clash, so one that gets here is a bug. Paths are compared
 * lowercased because case-insensitive file systems would silently merge them.
 */
function assertNoClashes(paths: string[]): void {
  const folded = new Map<string, string>();
  for (const path of paths) {
    const key = path.toLowerCase();
    const first = folded.get(key);
    if (first !== undefined) {
      throw new Error(`Two outputs share the path ${first} and ${path}`);
    }
    folded.set(key, path);
  }
  for (const path of paths) {
    const parts = path.toLowerCase().split("/");
    for (let end = 1; end < parts.length; end++) {
      if (folded.has(parts.slice(0, end).join("/"))) {
        throw new Error(
          `${path} would be inside another output that is a file`,
        );
      }
    }
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
