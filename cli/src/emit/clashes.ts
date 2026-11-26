import type { Diagnostic } from "../diagnostics/diagnostic";
import type { OutputFile } from "./write";

const RESERVED_FOLDER = "_sheaf/";
const IMAGE_FOLDER = "_sheaf/images/";

/**
 * Finds the files of `static/` that would overwrite, or be overwritten by,
 * what Sheaf generates, or each other. Paths are compared lowercased, as
 * `DUPLICATE PAGE` does, because case-insensitive file systems would merge them.
 * Each static file is reported once, for the first problem found.
 */
export function staticClashes(
  outputs: OutputFile[],
  staticFiles: OutputFile[],
): Diagnostic[] {
  const files = new Map<string, Claimed>();
  const folders = new Map<string, Claimed>();
  const claim = (claimed: Claimed) => {
    files.set(claimed.path.toLowerCase(), claimed);
    const parts = claimed.path.toLowerCase().split("/");
    for (let end = 1; end < parts.length; end++) {
      folders.set(parts.slice(0, end).join("/"), claimed);
    }
  };
  for (const output of outputs) {
    const aliasOf = output.kind === "text" ? output.aliasOf : undefined;
    claim({
      path: output.path,
      static: false,
      ...(aliasOf !== undefined && { aliasOf }),
    });
  }

  const diagnostics: Diagnostic[] = [];
  for (const { path } of staticFiles) {
    const mine: Claimed = { path, static: true };
    const problem = reservedClash(mine) ?? findClash(mine, files, folders);
    if (problem !== undefined) diagnostics.push(problem);
    claim(mine);
  }
  return diagnostics;
}

/** A path taken by a static file or an output; a redirect page has `aliasOf`. */
type Claimed = { path: string; static: boolean; aliasOf?: string };

function reservedClash({ path }: Claimed): Diagnostic | undefined {
  if (!path.toLowerCase().startsWith(RESERVED_FOLDER)) return undefined;
  return clash(
    `static/${path} is in /_sheaf/, which Sheaf reserves for its own files.`,
    "Paths starting with `/_sheaf/` are reserved for Sheaf. Move the file elsewhere in `static/`.",
  );
}

function findClash(
  mine: Claimed,
  files: Map<string, Claimed>,
  folders: Map<string, Claimed>,
): Diagnostic | undefined {
  const key = mine.path.toLowerCase();
  const same = files.get(key);
  if (same !== undefined) return samePath(mine, same);

  const parts = key.split("/");
  for (let end = 1; end < parts.length; end++) {
    const file = files.get(parts.slice(0, end).join("/"));
    if (file !== undefined) {
      return clash(
        `static/${mine.path} needs ${file.path} to be a folder, but ${describe(file)} is a file.`,
        moveHint(file),
      );
    }
  }

  const inside = folders.get(key);
  if (inside !== undefined) {
    return clash(
      `static/${mine.path} is a file, but ${describe(inside)} needs it to be a folder.`,
      moveHint(inside),
    );
  }
  return undefined;
}

function samePath(mine: Claimed, other: Claimed): Diagnostic {
  if (other.static) {
    return clash(
      `static/${other.path} and static/${mine.path} are the same file on a case-insensitive file system.`,
      "Rename one of them, so the site builds the same everywhere.",
    );
  }
  return clash(
    `static/${mine.path} would replace the ${describe(other)} that Sheaf generates.`,
    moveHint(other),
  );
}

/**
 * Names an output by its kind. Apart from redirects, the path alone tells them
 * apart: feeds and the sitemap are the only `.xml`.
 */
function describe({ path, static: isStatic, aliasOf }: Claimed): string {
  if (isStatic) return `static/${path}`;
  if (aliasOf !== undefined) return `redirect ${path} (alias of ${aliasOf})`;
  if (path.toLowerCase().startsWith(IMAGE_FOLDER)) {
    return `image variant ${path}`;
  }
  if (path.endsWith(".xml")) return path;
  return `page ${path}`;
}

function moveHint(other: Claimed): string {
  if (other.static) return "Rename or delete one of them.";
  if (other.aliasOf !== undefined) {
    return `Rename or delete the static file, or change the alias in ${other.aliasOf}.`;
  }
  return "Rename or delete the static file, or change the route that generates the other.";
}

function clash(message: string, hint: string): Diagnostic {
  return { severity: "error", title: "STATIC FILE CLASH", message, hint };
}
