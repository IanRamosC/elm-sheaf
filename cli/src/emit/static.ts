import { lstat, readdir, realpath, stat } from "node:fs/promises";
import { isAbsolute, join, relative, sep } from "node:path";
import type { Diagnostic } from "../diagnostics/diagnostic";
import { err, ok, type Result } from "../result";
import type { OutputFile } from "./write";

/**
 * Lists the files under `static/` that are copied into `dist/` as they are.
 * Symlinks are followed, so a linked asset is a real file in `dist/`, but only
 * while they stay inside the site's folder: a link out of it would publish
 * whatever it points at, such as a key in the home folder of the machine
 * building a site someone cloned. Hidden files are kept, because
 * `.well-known/` belongs on the web server.
 *
 * Diagnostics carry no `sourcePath`, since the file behind a bad link is
 * exactly what must not be read.
 */
export async function listStaticFiles(
  siteRoot: string,
): Promise<Result<OutputFile[], Diagnostic[]>> {
  const walk: Walk = {
    root: await realpath(siteRoot),
    files: [],
    problems: [],
  };
  try {
    await lstat(join(siteRoot, "static"));
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return ok([]);
    throw error;
  }
  await visit(walk, siteRoot, "static", []);
  return walk.problems.length > 0 ? err(walk.problems) : ok(walk.files);
}

type Walk = { root: string; files: OutputFile[]; problems: Diagnostic[] };

/**
 * Visits `path` (relative to the site root, with `/` separators). `ancestors`
 * are the real paths of the folders above it, which catch a link to one of
 * them before it recurses forever.
 */
async function visit(
  walk: Walk,
  siteRoot: string,
  path: string,
  ancestors: string[],
): Promise<void> {
  let real: string;
  try {
    real = await realpath(join(siteRoot, path));
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
    walk.problems.push(brokenSymlink(path));
    return;
  }
  if (!isInside(walk.root, real)) {
    walk.problems.push(symlinkOutsideSite(path, real));
    return;
  }

  const target = await stat(real);
  if (target.isFile()) {
    walk.files.push({
      kind: "copy",
      path: path.slice("static/".length),
      source: real,
    });
  } else if (target.isDirectory()) {
    if (ancestors.includes(real)) {
      walk.problems.push(symlinkLoop(path));
      return;
    }
    const names = (await readdir(real)).sort();
    for (const name of names) {
      await visit(walk, siteRoot, `${path}/${name}`, [...ancestors, real]);
    }
  }
}

function isInside(folder: string, path: string): boolean {
  const fromFolder = relative(folder, path);
  return (
    fromFolder !== ".." &&
    !fromFolder.startsWith(`..${sep}`) &&
    !isAbsolute(fromFolder)
  );
}

function brokenSymlink(path: string): Diagnostic {
  return {
    severity: "error",
    title: "BROKEN SYMLINK",
    message: `\`${path}\` is a symlink to a file that does not exist, so I cannot copy it into \`dist/\`.`,
    hint: "Point the symlink at an existing file, or delete it.",
  };
}

function symlinkOutsideSite(path: string, target: string): Diagnostic {
  return {
    severity: "error",
    title: "SYMLINK OUTSIDE SITE",
    message: `\`${path}\` leads to \`${target}\`, which is outside this site's folder. Everything in \`static/\` is published, so I only follow symlinks that stay inside the site.`,
    hint: "Copy the file into the site's folder, or point the symlink at a path inside it.",
  };
}

function symlinkLoop(path: string): Diagnostic {
  return {
    severity: "error",
    title: "SYMLINK LOOP",
    message: `\`${path}\` is a symlink to a folder that contains it, so copying it would never end.`,
    hint: "Point the symlink somewhere else, or delete it.",
  };
}
