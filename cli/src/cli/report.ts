import { readFile } from "node:fs/promises";
import { join } from "node:path";
import type { Diagnostic } from "../diagnostics/diagnostic";
import { renderDiagnostic } from "../diagnostics/render";
import { paint } from "./terminal";

/** A diagnostic as plain text, rendered once for both the terminal and the dev server's error page. */
export type RenderedDiagnostic = {
  severity: Diagnostic["severity"];
  text: string;
};

export async function renderDiagnostics(
  diagnostics: Diagnostic[],
  siteRoot: string,
): Promise<RenderedDiagnostic[]> {
  return Promise.all(
    diagnostics.map(async (diagnostic) => ({
      severity: diagnostic.severity,
      text: renderDiagnostic(
        diagnostic,
        await readSource(siteRoot, diagnostic),
      ),
    })),
  );
}

/** Prints the diagnostics with their headers coloured by severity. */
export function printDiagnostics(
  rendered: RenderedDiagnostic[],
  colour: boolean,
): void {
  for (const { severity, text } of rendered) {
    const [header = "", ...rest] = text.split("\n");
    const style = severity === "error" ? "red" : "yellow";
    write(`${[paint(style, header, colour), ...rest].join("\n")}\n`);
  }
}

/** Prints the line that ends a failed build or check. */
export function printErrorCount(
  rendered: RenderedDiagnostic[],
  colour: boolean,
): void {
  const errors = rendered.filter(({ severity }) => severity === "error");
  write(paint("red", `Found ${count(errors.length, "error")}`, colour));
}

export function count(amount: number, noun: string): string {
  return `${amount} ${noun}${amount === 1 ? "" : "s"}`;
}

export function write(line: string): void {
  process.stdout.write(`${line}\n`);
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
