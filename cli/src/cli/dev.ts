import { readdir, readFile, rm } from "node:fs/promises";
import { join } from "node:path";
import { type BuildSuccess, build } from "../build";
import { parseConfig } from "../config/config";
import { isErrno } from "../content/files";
import { startDevServer } from "../dev/server";
import { rebuildQueue, watchSite } from "../dev/watch";
import type { Diagnostic } from "../diagnostics/diagnostic";
import { renderDiagnostic } from "../diagnostics/render";
import { err, type Result } from "../result";
import {
  pagesSummary,
  printDiagnostics,
  printErrorCount,
  type RenderedDiagnostic,
  renderDiagnostics,
  write,
} from "./report";
import { paint, supportsColour } from "./terminal";

/**
 * Builds the site with drafts, serves it, and rebuilds and reloads the
 * browser after every change until SIGINT or SIGTERM. Each build goes to a
 * new folder under `.sheaf/dev/<pid>/`, so the server switches to a complete
 * site and never serves one half written; the pid keeps two `dev` runs on
 * one site out of each other's way.
 */
export async function runDev(
  siteRoot: string,
  port: number | undefined,
): Promise<number> {
  const devFolder = join(siteRoot, ".sheaf/dev");
  await removeStaleOutput(devFolder);

  const basePath = await readBasePath(siteRoot);
  const started = startDevServer({ basePath, port });
  if (!started.ok) {
    process.stderr.write(`${started.error}\n`);
    return 2;
  }
  const server = started.value;
  const output = join(devFolder, String(process.pid));
  const colour = supportsColour();
  write(`Serving at ${server.url}`);

  let buildNumber = 0;
  let shown: string | undefined;
  let stopping = false;
  let building = Promise.resolve();

  async function rebuild(): Promise<void> {
    if (stopping) return;
    buildNumber += 1;
    const folder = join(output, String(buildNumber));
    const startedAt = performance.now();
    const result = await buildCatchingCrashes(siteRoot, folder);
    // Ctrl-C stops the Elm compiler too, and that failure is not the site's.
    if (stopping) return;
    const seconds = ((performance.now() - startedAt) / 1000).toFixed(1);

    if (result.ok) {
      server.showSite(folder);
      if (shown !== undefined)
        await rm(shown, { recursive: true, force: true });
      shown = folder;
      printDiagnostics(
        await renderDiagnostics(result.value.warnings, siteRoot),
        colour,
      );
      const { pages, redirects } = result.value;
      const summary = pagesSummary(pages, redirects);
      write(paint("green", `Rebuilt ${summary} in ${seconds}s`, colour));
      await warnIfBasePathChanged(siteRoot, basePath, colour);
    } else {
      // A crash while writing can leave part of a site behind.
      await rm(folder, { recursive: true, force: true });
      showFailure(await renderDiagnostics(result.error, siteRoot));
      return;
    }
    server.reload();
  }

  function showFailure(rendered: RenderedDiagnostic[]): void {
    server.showErrors(rendered.map(({ text }) => text));
    printDiagnostics(rendered, colour);
    printErrorCount(rendered, colour);
    server.reload();
  }

  // Showing a build can fail too, say when the previous folder can't be deleted.
  function showCrash(error: unknown): void {
    if (stopping) return;
    const diagnostic = crashed(error);
    showFailure([
      { severity: "error", text: renderDiagnostic(diagnostic, undefined) },
    ]);
  }

  const queue = rebuildQueue(() => {
    building = rebuild();
    return building;
  }, showCrash);
  const watcher = watchSite(siteRoot, queue.request);
  queue.request();

  await nextSignal();
  stopping = true;
  watcher.close();
  server.stop();
  // A rejection here was already reported by the queue.
  await building.catch(() => undefined);
  await rm(output, { recursive: true, force: true });
  return 0;
}

/** `build` throws on bugs, the worker's timeout, or a file deleted mid-build; none of those should stop `dev`. */
async function buildCatchingCrashes(
  siteRoot: string,
  output: string,
): Promise<Result<BuildSuccess, Diagnostic[]>> {
  try {
    return await build(siteRoot, {
      mode: "drafts",
      now: new Date(),
      output,
      optimize: false,
      log: withoutDevModeNotice,
    });
  } catch (error) {
    return err([crashed(error)]);
  }
}

/** Elm prints this notice on every unoptimised run; it says nothing about the site. */
function withoutDevModeNotice(line: string): void {
  if (!line.startsWith("warn: Compiled in DEV mode")) write(line);
}

function crashed(error: unknown): Diagnostic {
  return {
    severity: "error",
    title: "SHEAF CRASHED",
    message:
      error instanceof Error ? (error.stack ?? error.message) : String(error),
    hint: "`sheaf dev` keeps running and builds again on the next change.",
  };
}

/** Removes the output of `dev` runs whose process has ended without cleaning up. */
async function removeStaleOutput(devFolder: string): Promise<void> {
  let entries: string[];
  try {
    entries = await readdir(devFolder);
  } catch (error) {
    if (isErrno(error) && error.code === "ENOENT") return;
    throw error;
  }
  for (const entry of entries) {
    if (/^\d+$/.test(entry) && !isRunning(Number(entry))) {
      await rm(join(devFolder, entry), { recursive: true, force: true });
    }
  }
}

function isRunning(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    // EPERM: the process exists but belongs to someone else.
    return isErrno(error) && error.code === "EPERM";
  }
}

/**
 * The server's base path is fixed when it starts. A `sheaf.json` that can't
 * be read yet gives `/`, and the first build reports what is wrong with it.
 */
async function readBasePath(siteRoot: string): Promise<string> {
  let text: string;
  try {
    text = await readFile(join(siteRoot, "sheaf.json"), "utf8");
  } catch {
    return "/";
  }
  const config = parseConfig(text, "sheaf.json");
  return config.ok ? config.value.basePath : "/";
}

async function warnIfBasePathChanged(
  siteRoot: string,
  served: string,
  colour: boolean,
): Promise<void> {
  const current = await readBasePath(siteRoot);
  if (current !== served) {
    const message = `The base path is now ${current}, but this server still serves ${served}. Restart \`sheaf dev\` to follow it.`;
    write(paint("yellow", message, colour));
  }
}

function nextSignal(): Promise<void> {
  return new Promise((resolve) => {
    const stop = () => {
      process.off("SIGINT", stop);
      process.off("SIGTERM", stop);
      resolve();
    };
    process.on("SIGINT", stop);
    process.on("SIGTERM", stop);
  });
}
