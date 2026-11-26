import { resolve } from "node:path";
import { ELM_NPM_VERSION } from "../init/project-files";

/** How Sheaf is running: from source under Bun, or as a standalone binary. */
export type Runtime = "bun" | "binary";

/**
 * Tells the two apart by the entry module's path. A binary made with
 * `bun build --compile` serves its modules from a virtual file system, which
 * Bun mounts at `/$bunfs/` on macOS and Linux and under `~BUN` on Windows.
 */
export function runtimeOf(entry: string): Runtime {
  return entry.startsWith("/$bunfs/") || /^[A-Z]:[\\/]~BUN[\\/]/i.test(entry)
    ? "binary"
    : "bun";
}

/**
 * What to run after `init` created a site in `folder`. A site made by the
 * standalone binary has no `node_modules` to provide Elm or `sheaf`, so it
 * relies on both being on the PATH.
 */
export function nextSteps(
  folder: string,
  cwd: string,
  runtime: Runtime,
): string[] {
  const cd =
    resolve(cwd, folder) === resolve(cwd) ? [] : [`cd ${shellQuoted(folder)}`];
  if (runtime === "bun") return [...cd, "bun install", "bunx sheaf dev"];
  return [
    `Install Elm 0.19.3 (npm install -g elm@${ELM_NPM_VERSION}, or from https://github.com/elm/compiler/releases) if it isn't on your PATH.`,
    ...cd,
    "sheaf dev",
  ];
}

/**
 * Quotes a folder name for the shell only when it needs it. Single quotes
 * keep `$` and backticks from being expanded; a single quote inside them
 * closes the quotes, adds an escaped quote and opens them again.
 */
function shellQuoted(path: string): string {
  return /^[\w@%+=:,./-]+$/.test(path)
    ? path
    : `'${path.replaceAll("'", "'\\''")}'`;
}
