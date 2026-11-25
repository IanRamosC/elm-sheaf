import { type FSWatcher, readFileSync, statSync, watch } from "node:fs";
import { dirname, isAbsolute, join, relative, resolve, sep } from "node:path";

const debounceMilliseconds = 100;

/** Folders that builds, Elm and package managers write to; a change there is never the author's. */
const ignoredFolders = new Set([".sheaf", "elm-stuff", "node_modules", "dist"]);

/**
 * The files and folders a build reads, resolved against the site root: the
 * content, the static files, both configuration files and the Elm source
 * directories. `.sheaf/gen` is a source directory too, but every build
 * rewrites it, so watching it would make each build start the next.
 */
export function watchedPaths(siteRoot: string, elmJson: string): string[] {
  return pathsFor(siteRoot, parseSourceDirectories(elmJson) ?? []);
}

function pathsFor(siteRoot: string, sourceDirectories: string[]): string[] {
  const generated = resolve(siteRoot, ".sheaf");
  const paths = ["content", "static", "sheaf.json", "elm.json"]
    .concat(sourceDirectories)
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

function readSourceDirectories(elmJsonPath: string): string[] | undefined {
  try {
    return parseSourceDirectories(readFileSync(elmJsonPath, "utf8"));
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
  const configFiles = [join(root, "sheaf.json"), elmJsonPath];
  // When elm.json can't be read, the build reports why; until then the last good list stands.
  let sourceDirectories = readSourceDirectories(elmJsonPath) ?? [];
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
    const folders = pathsFor(root, sourceDirectories).filter(
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
    for (const [key, { folder, recursive }] of wanted) {
      if (!watchers.has(key)) {
        watchers.set(key, open(key, folder, recursive));
      }
    }
  }

  function open(key: string, folder: string, recursive: boolean): FSWatcher {
    const watcher = watch(folder, { recursive }, (_event, filename) => {
      if (filename === null) return;
      const path = resolve(folder, filename);
      if (isIgnored(root, path)) return;

      if (path === elmJsonPath) {
        sourceDirectories =
          readSourceDirectories(elmJsonPath) ?? sourceDirectories;
      }
      if (!recursive || path === elmJsonPath) refresh();
      // A shallow watcher also sees unrelated names, and parents of folders still missing.
      const watched = pathsFor(root, sourceDirectories);
      if (recursive || watched.some((input) => isWithin(path, input))) {
        changed();
      }
    });
    // A watched folder that is deleted errors on some platforms; its parent's watcher takes over.
    watcher.on("error", () => {
      watcher.close();
      watchers.delete(key);
      refresh();
    });
    return watcher;
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
 * single run after it, so builds never overlap and none is lost. `run` must
 * not reject.
 */
export function rebuildQueue(run: () => Promise<void>): { request(): void } {
  let running = false;
  let again = false;

  async function drain(): Promise<void> {
    running = true;
    do {
      again = false;
      await run();
    } while (again);
    running = false;
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
