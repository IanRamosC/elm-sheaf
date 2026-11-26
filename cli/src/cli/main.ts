import { join } from "node:path";
import { parseArgs } from "node:util";
import packageJson from "../../package.json";
import { build } from "../build";
import { initSite } from "../init/init";
import { runDev } from "./dev";
import { nextSteps, runtimeOf } from "./next-steps";
import {
  count,
  printDiagnostics,
  printErrorCount,
  renderDiagnostics,
  write,
} from "./report";
import { paint, supportsColour } from "./terminal";

const HELP = `Usage: sheaf <command> [options]

Commands:
  sheaf build [--drafts] [--site-url <url>]   Render the site into dist/
  sheaf check [--drafts] [--site-url <url>]   Run every build stage without writing dist/
  sheaf dev [--port <n>]                      Serve the site with drafts, rebuilding on every change
  sheaf init <folder> [--local <path>]        Create a site in an empty or new folder

Options:
  --drafts          Include drafts and documents dated in the future
  --site-url <url>  Use this siteUrl instead of the one in sheaf.json
  --port <n>        Serve on this port instead of the first free one from 4000
  --local <path>    Use a checkout of the Sheaf repository instead of the published packages
  -h, --help        Show this help
  -v, --version     Show the version
`;

type Command = "build" | "check";

/** What to run, once the options are known to belong to the command. */
type Invocation =
  | ({ command: Command } & CommandOptions)
  | { command: "dev"; port: number | undefined }
  | { command: "init"; folder: string; local: string | undefined };

/**
 * Runs the command line and returns the exit code: 0 success, 1 errors in the
 * site, 2 bad usage or a Bun older than `engines.bun` in package.json.
 */
export async function main(args: string[]): Promise<number> {
  const parsed = parseArguments(args);
  if (parsed === undefined) return usageError();
  const { values, positionals } = parsed;

  if (values.help) {
    process.stdout.write(HELP);
    return 0;
  }
  if (values.version) {
    process.stdout.write(`${packageJson.version}\n`);
    return 0;
  }
  const invocation = invocationOf(positionals, values);
  if (invocation === undefined) return usageError();

  const unsupported = unsupportedBun(Bun.version, packageJson.engines.bun);
  if (unsupported !== undefined) {
    process.stderr.write(`${unsupported}\n`);
    return 2;
  }
  if (invocation.command === "dev") {
    return runDev(process.cwd(), invocation.port);
  }
  if (invocation.command === "init") {
    return runInit(invocation.folder, invocation.local);
  }
  return runCommand(invocation.command, invocation);
}

type Values = NonNullable<ReturnType<typeof parseArguments>>["values"];

/**
 * Matches the options to the command. `dev` always includes drafts and has
 * no siteUrl of its own to replace, so those options are mistakes there.
 */
function invocationOf(
  positionals: string[],
  values: Values,
): Invocation | undefined {
  const [command, ...extra] = positionals;
  const { drafts, "site-url": siteUrl, port, local } = values;

  if (command === "init") {
    const [folder, ...more] = extra;
    if (folder === undefined || more.length > 0) return undefined;
    if (drafts !== undefined || siteUrl !== undefined || port !== undefined) {
      return undefined;
    }
    return { command, folder, local };
  }
  if (extra.length > 0 || local !== undefined) return undefined;

  if (command === "dev") {
    if (drafts !== undefined || siteUrl !== undefined) return undefined;
    if (port === undefined) return { command, port };
    const parsed = parsePort(port);
    return parsed === undefined ? undefined : { command, port: parsed };
  }
  if ((command === "build" || command === "check") && port === undefined) {
    return { command, drafts: drafts === true, siteUrl };
  }
  return undefined;
}

function parseArguments(args: string[]) {
  try {
    return parseArgs({
      args,
      allowPositionals: true,
      options: {
        drafts: { type: "boolean" },
        "site-url": { type: "string" },
        port: { type: "string" },
        local: { type: "string" },
        help: { type: "boolean", short: "h" },
        version: { type: "boolean", short: "v" },
      },
    });
  } catch {
    return undefined;
  }
}

/**
 * Explains why this Bun cannot run Sheaf, or gives `undefined` when it can.
 * Bun is a floor rather than an exact version: a newer Bun may encode images
 * differently, but their file names hash the Bun version, so it only renames
 * them.
 */
export function unsupportedBun(
  version: string,
  supported: string,
): string | undefined {
  if (Bun.semver.satisfies(version, supported)) return undefined;
  return `Sheaf needs Bun ${supported}, but this is Bun ${version}. Run \`bun upgrade\` to update it.`;
}

/** Port 0 lets the system pick one; only the tests use it, so the help doesn't mention it. */
function parsePort(text: string): number | undefined {
  const port = Number(text);
  return /^\d+$/.test(text) && port <= 65535 ? port : undefined;
}

function usageError(): number {
  process.stderr.write(HELP);
  return 2;
}

async function runInit(
  folder: string,
  local: string | undefined,
): Promise<number> {
  const colour = supportsColour();
  const result = await initSite(folder, {
    local,
    today: new Date().toISOString().slice(0, 10),
  });
  if (!result.ok) {
    const rendered = await renderDiagnostics(result.error, process.cwd());
    printDiagnostics(rendered, colour);
    printErrorCount(rendered, colour);
    return 1;
  }

  write(paint("green", `Created a site in ${folder}`, colour));
  write("\nNext steps:");
  for (const step of nextSteps(folder, process.cwd(), runtimeOf(Bun.main))) {
    write(`  ${step}`);
  }
  return 0;
}

type CommandOptions = { drafts: boolean; siteUrl: string | undefined };

async function runCommand(
  command: Command,
  { drafts, siteUrl }: CommandOptions,
): Promise<number> {
  const siteRoot = process.cwd();
  const colour = supportsColour();
  const started = performance.now();

  const result = await build(siteRoot, {
    mode: drafts ? "drafts" : "production",
    now: new Date(),
    output: command === "build" ? join(siteRoot, "dist") : undefined,
    optimize: true,
    ...(siteUrl === undefined ? {} : { siteUrl }),
    log: write,
  });
  const seconds = ((performance.now() - started) / 1000).toFixed(1);

  if (result.ok) {
    printDiagnostics(
      await renderDiagnostics(result.value.warnings, siteRoot),
      colour,
    );
    const verb = command === "build" ? "Built" : "Checked";
    const { pages } = result.value;
    write(
      paint("green", `${verb} ${count(pages, "page")} in ${seconds}s`, colour),
    );
    return 0;
  }

  const rendered = await renderDiagnostics(result.error, siteRoot);
  printDiagnostics(rendered, colour);
  printErrorCount(rendered, colour);
  return 1;
}
