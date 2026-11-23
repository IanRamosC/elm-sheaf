import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { parseArgs } from "node:util";
import packageJson from "../../package.json";
import { build } from "../build";
import type { Diagnostic } from "../diagnostics/diagnostic";
import { renderDiagnostic } from "../diagnostics/render";
import { paint, supportsColour } from "./terminal";

const HELP = `Usage: sheaf <command> [options]

Commands:
  sheaf build [--drafts]   Render the site into dist/
  sheaf check [--drafts]   Run every build stage without writing dist/

Options:
  --drafts      Include drafts and documents dated in the future
  -h, --help    Show this help
  -v, --version Show the version
`;

type Command = "build" | "check";

/** Runs the command line and returns the exit code: 0 success, 1 errors in the site, 2 bad usage. */
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
  const [command, ...extra] = positionals;
  if ((command !== "build" && command !== "check") || extra.length > 0) {
    return usageError();
  }
  return runCommand(command, values.drafts === true);
}

function parseArguments(args: string[]) {
  try {
    return parseArgs({
      args,
      allowPositionals: true,
      options: {
        drafts: { type: "boolean" },
        help: { type: "boolean", short: "h" },
        version: { type: "boolean", short: "v" },
      },
    });
  } catch {
    return undefined;
  }
}

function usageError(): number {
  process.stderr.write(HELP);
  return 2;
}

async function runCommand(command: Command, drafts: boolean): Promise<number> {
  const siteRoot = process.cwd();
  const colour = supportsColour();
  const started = performance.now();

  const result = await build(siteRoot, {
    mode: drafts ? "drafts" : "production",
    write: command === "build",
    now: new Date(),
  });
  const seconds = ((performance.now() - started) / 1000).toFixed(1);

  if (result.ok) {
    for (const line of result.value.output) write(line);
    await printDiagnostics(result.value.warnings, siteRoot, colour);
    const verb = command === "build" ? "Built" : "Checked";
    const { pages } = result.value;
    write(
      paint("green", `${verb} ${count(pages, "page")} in ${seconds}s`, colour),
    );
    return 0;
  }

  await printDiagnostics(result.error, siteRoot, colour);
  const errors = result.error.filter(({ severity }) => severity === "error");
  write(paint("red", `Found ${count(errors.length, "error")}`, colour));
  return 1;
}

function count(amount: number, noun: string): string {
  return `${amount} ${noun}${amount === 1 ? "" : "s"}`;
}

function write(line: string): void {
  process.stdout.write(`${line}\n`);
}

async function printDiagnostics(
  diagnostics: Diagnostic[],
  siteRoot: string,
  colour: boolean,
): Promise<void> {
  for (const diagnostic of diagnostics) {
    const source = await readSource(siteRoot, diagnostic);
    const [header = "", ...rest] = renderDiagnostic(diagnostic, source).split(
      "\n",
    );
    const style = diagnostic.severity === "error" ? "red" : "yellow";
    write(`${[paint(style, header, colour), ...rest].join("\n")}\n`);
  }
}

/** A diagnostic may name something that is not a readable file, such as a folder; it then has no excerpt. */
async function readSource(
  siteRoot: string,
  { sourcePath }: Diagnostic,
): Promise<string | undefined> {
  if (sourcePath === undefined) return undefined;
  try {
    return await readFile(join(siteRoot, sourcePath), "utf8");
  } catch {
    return undefined;
  }
}
