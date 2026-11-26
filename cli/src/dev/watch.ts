import { type FSWatcher, readFileSync, statSync, watch } from "node:fs";
import { dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { isErrno } from "../content/files";
import { isObject } from "../json";

const debounceMilliseconds = 100;

/** Folders that builds, Elm and package managers write to; a change there is never the author's. */
const ignoredFolders = new Set([".sheaf", "elm-stuff", "node_modules", "dist"]);

/**
 * The files and folders a build reads, resolved against the site root: the
 * content, the static files, both configuration files, the Elm source
 * directories and the grammars and themes `sheaf.json` names. `.sheaf/gen`
 * is a source directory too, but every build rewrites it, so watching it
 * would make each build start the next.
 */
export function watchedPaths(
  siteRoot: string,
  elmJson: string,
  sheafJson: string,
): string[] {
  return pathsFor(siteRoot, [
    ...(parseSourceDirectories(elmJson) ?? []),
    ...(parseHighlightFiles(sheafJson) ?? []),
  ]);
}

/** `named` are the paths the configuration files give, which change with them. */
function pathsFor(siteRoot: string, named: string[]): string[] {
  const generated = resolve(siteRoot, ".sheaf");
  const paths = ["content", "static", "sheaf.json", "elm.json"]
    .concat(named)
    .map((path) => resolve(siteRoot, path))
    .filter((path) => !isWithin(generated, path));
  return [...new Set(paths)];
}

function parseSourceDirectories(elmJson: string): string[] | undefined {
  try {
    const directories: unknown = JSON.parse(elmJson)["source-directories"];
    return Array.isArray(directories) &&
      directories.every((directory) => typeof directory === "string")
      ? directories
      : undefined;
  } catch {
    return undefined;
  }
}

/** The files of `highlight.grammars` and `highlight.themes`; the build reports what is wrong with them. */
function parseHighlightFiles(sheafJson: string): string[] | undefined {
  try {
    const highlight: unknown = JSON.parse(sheafJson).highlight;
    if (!isObject(highlight)) return [];
    return [highlight.grammars, highlight.themes].flatMap((paths) =>
      isObject(paths)
        ? Object.values(paths).filter((path) => typeof path === "string")
        : [],
    );
  } catch {
    return undefined;
  }
}

/** What `parse` makes of the file at `path`, or `undefined` when it can't be read. */
function readWith<T>(
  path: string,
  parse: (text: string) => T | undefined,
): T | undefined {
  try {
    return parse(readFileSync(path, "utf8"));
  } catch {
    return undefined;
  }
}

/**
 * Calls `onChange` once a burst of changes to the site's inputs has settled.
 *
 * Folders are watched rather than files, because a watcher on a single file
 * loses it on Linux when an editor saves by writing a copy and renaming it.
 * A folder that doesn't exist yet is waited for by watching its nearest
 * existing parent, and gets its own watcher when it appears.
 */
export function watchSite(
  siteRoot: string,
  onChange: () => void,
): { close(): void } {
  const root = resolve(siteRoot);
  const elmJsonPath = join(root, "elm.json");
  const sheafJsonPath = join(root, "sheaf.json");
  const configFiles = [sheafJsonPath, elmJsonPath];
  // When a configuration file can't be read, the build reports why; until
  // then the last good list stands.
  let sourceDirectories = readWith(elmJsonPath, parseSourceDirectories) ?? [];
  let highlightFiles = readWith(sheafJsonPath, parseHighlightFiles) ?? [];
  const named = () => [...sourceDirectories, ...highlightFiles];
  const watchers = new Map<string, FSWatcher>();
  let timer: ReturnType<typeof setTimeout> | undefined;

  function changed(): void {
    clearTimeout(timer);
    timer = setTimeout(onChange, debounceMilliseconds);
  }

  function refresh(): void {
    const wanted = new Map<string, { folder: string; recursive: boolean }>();
    const want = (folder: string, recursive: boolean) =>
      wanted.set(`${recursive}:${folder}`, { folder, recursive });

    want(root, false);
    const folders = pathsFor(root, named()).filter(
      (path) => !configFiles.includes(path),
    );
    for (const path of folders) {
      if (isDirectory(path)) {
        want(path, true);
      } else {
        want(nearestFolder(dirname(path)), false);
      }
    }

    for (const [key, watcher] of watchers) {
      if (!wanted.has(key)) {
        watcher.close();
        watchers.delete(key);
      }
    }
    let vanished = false;
    for (const [key, { folder, recursive }] of wanted) {
      if (!watchers.has(key)) {
        const watcher = open(key, folder, recursive);
        if (watcher === undefined) {
          vanished ||= folder !== root;
        } else {
          watchers.set(key, watcher);
        }
      }
    }
    // Looking again finds the folder missing, so its parent is watched instead.
    // Without the site root there is nothing left to wait on.
    if (vanished) refresh();
  }

  /** Gives `undefined` when the folder was deleted after `refresh` saw it, as `git checkout` can do. */
  function open(
    key: string,
    folder: string,
    recursive: boolean,
  ): FSWatcher | undefined {
    let watcher: FSWatcher;
    try {
      watcher = watch(folder, { recursive }, (_event, filename) =>
        onEvent(folder, recursive, filename),
      );
    } catch (error) {
      if (isErrno(error) && error.code === "ENOENT") return undefined;
      throw error;
    }
    // A watched folder that is deleted errors on some platforms; its parent's watcher takes over.
    watcher.on("error", () => {
      watcher.close();
      watchers.delete(key);
      refresh();
    });
    return watcher;
  }

  function onEvent(
    folder: string,
    recursive: boolean,
    filename: string | null,
  ): void {
    if (filename === null) return;
    const path = resolve(folder, filename);
    if (isIgnored(root, path)) return;

    if (path === elmJsonPath) {
      sourceDirectories =
        readWith(elmJsonPath, parseSourceDirectories) ?? sourceDirectories;
    }
    if (path === sheafJsonPath) {
      highlightFiles =
        readWith(sheafJsonPath, parseHighlightFiles) ?? highlightFiles;
    }
    if (!recursive || configFiles.includes(path)) refresh();
    // A shallow watcher also sees unrelated names, and parents of folders still missing.
    const watched = pathsFor(root, named());
    if (recursive || watched.some((input) => isWithin(path, input))) {
      changed();
    }
  }

  refresh();
  return {
    close() {
      clearTimeout(timer);
      for (const watcher of watchers.values()) {
        watcher.close();
      }
      watchers.clear();
    },
  };
}

/**
 * Runs `run` at once when idle. Requests made while it runs collapse into a
 * single run after it, so builds never overlap and none is lost. A run that
 * rejects goes to `onError`, and the queue carries on.
 */
export function rebuildQueue(
  run: () => Promise<void>,
  onError: (error: unknown) => void,
): { request(): void } {
  let running = false;
  let again = false;

  async function drain(): Promise<void> {
    running = true;
    try {
      do {
        again = false;
        try {
          await run();
        } catch (error) {
          onError(error);
        }
      } while (again);
    } finally {
      running = false;
    }
  }

  return {
    request() {
      if (running) {
        again = true;
      } else {
        void drain();
      }
    },
  };
}

function isIgnored(siteRoot: string, path: string): boolean {
  const [first = ""] = relative(siteRoot, path).split(sep);
  return ignoredFolders.has(first);
}

/** Whether `path` is `folder` or somewhere inside it. */
function isWithin(folder: string, path: string): boolean {
  const between = relative(folder, path);
  return (
    between === "" ||
    (!between.startsWith(`..${sep}`) &&
      between !== ".." &&
      !isAbsolute(between))
  );
}

function nearestFolder(path: string): string {
  let folder = path;
  while (!isDirectory(folder) && dirname(folder) !== folder) {
    folder = dirname(folder);
  }
  return folder;
}

function isDirectory(path: string): boolean {
  try {
    return statSync(path).isDirectory();
  } catch {
    return false;
  }
}
