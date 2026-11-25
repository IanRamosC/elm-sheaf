import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { rebuildQueue, watchedPaths, watchSite } from "../../src/dev/watch";

/** Longer than the debounce, so every change made before it has been reported. */
const SETTLE = 300;

let root: string;
const watchers: { close(): void }[] = [];

beforeEach(() => {
  root = mkdtempSync(join(tmpdir(), "sheaf-watch-"));
  mkdirSync(join(root, "content"));
  mkdirSync(join(root, "src"));
});

afterEach(() => {
  for (const watcher of watchers.splice(0)) {
    watcher.close();
  }
  rmSync(root, { recursive: true, force: true });
});

function elmJson(sourceDirectories: string[]): string {
  return JSON.stringify({ "source-directories": sourceDirectories });
}

/**
 * macOS reports changes made a few milliseconds before a watcher starts, so
 * the setup is given time to fall out of that window first.
 */
async function watchCounting(): Promise<{ calls: () => number }> {
  await Bun.sleep(50);
  let calls = 0;
  watchers.push(watchSite(root, () => calls++));
  return { calls: () => calls };
}

async function waitUntil(condition: () => boolean): Promise<void> {
  const deadline = performance.now() + 2000;
  while (!condition()) {
    if (performance.now() > deadline) {
      throw new Error("Timed out waiting for a change to be reported");
    }
    await Bun.sleep(10);
  }
}

describe("watchedPaths", () => {
  test("lists the site's inputs, without generated folders or duplicates", () => {
    const paths = watchedPaths(
      "/site",
      elmJson(["src", ".sheaf/gen", "../shared/src", "src"]),
    );

    expect(paths).toEqual([
      resolve("/site/content"),
      resolve("/site/static"),
      resolve("/site/sheaf.json"),
      resolve("/site/elm.json"),
      resolve("/site/src"),
      resolve("/shared/src"),
    ]);
  });

  test("keeps the site root as a source directory", () => {
    expect(watchedPaths("/site", elmJson(["."]))).toContain(resolve("/site"));
  });
});

describe("watchSite", () => {
  test("reports two quick writes as one change", async () => {
    writeFileSync(join(root, "elm.json"), elmJson(["src"]));
    const watcher = await watchCounting();

    writeFileSync(join(root, "content/a.md"), "one");
    await Bun.sleep(10);
    writeFileSync(join(root, "content/a.md"), "two");
    await Bun.sleep(SETTLE);

    expect(watcher.calls()).toBe(1);
  });

  test("watches a folder created after it started", async () => {
    writeFileSync(join(root, "elm.json"), elmJson(["src"]));
    const watcher = await watchCounting();

    mkdirSync(join(root, "static"));
    await waitUntil(() => watcher.calls() === 1);
    writeFileSync(join(root, "static/style.css"), "body{}");
    await waitUntil(() => watcher.calls() === 2);
  });

  test("ignores generated folders when the site root is a source directory", async () => {
    writeFileSync(join(root, "elm.json"), elmJson(["."]));
    mkdirSync(join(root, ".sheaf/gen"), { recursive: true });
    mkdirSync(join(root, "elm-stuff"));
    const watcher = await watchCounting();

    writeFileSync(join(root, ".sheaf/gen/Content.elm"), "module Content");
    writeFileSync(join(root, "elm-stuff/lock"), "");
    await Bun.sleep(SETTLE);
    expect(watcher.calls()).toBe(0);

    writeFileSync(join(root, "Main.elm"), "module Main");
    await waitUntil(() => watcher.calls() === 1);
  });

  test("follows the source directories when elm.json changes", async () => {
    writeFileSync(join(root, "elm.json"), elmJson(["src"]));
    mkdirSync(join(root, "lib"));
    const watcher = await watchCounting();

    writeFileSync(join(root, "elm.json"), elmJson(["src", "lib"]));
    await waitUntil(() => watcher.calls() === 1);
    writeFileSync(join(root, "lib/Extra.elm"), "module Extra");
    await waitUntil(() => watcher.calls() === 2);
  });
});

describe("rebuildQueue", () => {
  test("runs at once when idle, and queues one run however many requests arrive during one", async () => {
    const finishers: (() => void)[] = [];
    let running = 0;
    let overlapped = false;
    const queue = rebuildQueue(async () => {
      running++;
      overlapped ||= running > 1;
      await new Promise<void>((done) => finishers.push(done));
      running--;
    });

    queue.request();
    expect(finishers).toHaveLength(1);

    queue.request();
    queue.request();
    queue.request();
    expect(finishers).toHaveLength(1);

    finishers[0]?.();
    await waitUntil(() => finishers.length === 2);
    finishers[1]?.();
    await Bun.sleep(10);

    expect(finishers).toHaveLength(2);

    queue.request();
    expect(finishers).toHaveLength(3);
    finishers[2]?.();
    expect(overlapped).toBe(false);
  });
});
