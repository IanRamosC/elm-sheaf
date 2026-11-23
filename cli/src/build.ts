import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { type Config, parseConfig } from "./config/config";
import type { SourceDocument } from "./content/document";
import {
  type BuildMode,
  loadContent,
  readCollectionNames,
  readContentFiles,
} from "./content/load";
import type { Diagnostic } from "./diagnostics/diagnostic";
import { compileElm, findElm } from "./elm/compile";
import { generateElm } from "./elm/generate";
import { assignValueNames } from "./elm/names";
import { encodeRequest, type ParsedDocument } from "./elm/protocol";
import { runElm } from "./elm/run";
import { writeGenerated, writeSite } from "./emit/write";
import { checkLinks } from "./markdown/links";
import { parseMarkdown } from "./markdown/parse";
import { collect, err, ok, type Result } from "./result";

export type BuildOptions = {
  mode: BuildMode;
  /** `false` is `sheaf check`: every stage runs, but `dist/` is left alone. */
  write: boolean;
  /** Decides which dated documents are not yet published. */
  now: Date;
};

export type BuildSuccess = {
  pages: number;
  warnings: Diagnostic[];
  /** What the Elm worker logged; the CLI prints it. */
  output: string[];
};

/**
 * Runs the pipeline in order. A stage that found errors ends the build, but
 * only after it has reported everything it can see, so one run shows all the
 * problems of that stage. `check` compiles with `--optimize` like `build`, so
 * it catches whatever `build` would reject, such as `Debug` calls.
 */
export async function build(
  siteRoot: string,
  options: BuildOptions,
): Promise<Result<BuildSuccess, Diagnostic[]>> {
  const config = await readConfig(siteRoot);
  if (!config.ok) return config;

  const files = await readContentFiles(siteRoot);
  const documents = loadContent(files, config.value, options.now, options.mode);
  if (!documents.ok) return documents;

  const parsed = parseDocuments(documents.value);
  if (!parsed.ok) return parsed;

  const names = assignValueNames(documents.value);
  if (!names.ok) return names;

  const collections = await readCollectionNames(siteRoot);
  await writeGenerated(
    siteRoot,
    generateElm(collections, documents.value, names.value),
  );

  const elm = await findElm(siteRoot);
  if (!elm.ok) return elm;
  const compiled = await compileElm(siteRoot, {
    elm: elm.value,
    optimize: true,
  });
  if (!compiled.ok) return compiled;

  const request = encodeRequest(
    {
      siteUrl: config.value.siteUrl.href,
      basePath: config.value.basePath,
      mode: options.mode,
    },
    collections,
    parsed.value,
  );
  const ran = await runElm(compiled.value, request);
  if (!ran.ok) return ran;

  const { pages, diagnostics } = ran.value.response;
  if (diagnostics.some(({ severity }) => severity === "error")) {
    return err(diagnostics);
  }
  if (options.write) await writeSite(siteRoot, pages);
  return ok({
    pages: pages.length,
    warnings: diagnostics,
    output: ran.value.output,
  });
}

async function readConfig(
  siteRoot: string,
): Promise<Result<Config, Diagnostic[]>> {
  let text: string;
  try {
    text = await readFile(join(siteRoot, "sheaf.json"), "utf8");
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
    return err([
      {
        severity: "error",
        title: "NO SHEAF.JSON",
        message: `There is no sheaf.json in ${siteRoot}, so this does not look like a Sheaf site.`,
        hint: 'Run this command in your site\'s folder, or create sheaf.json with { "siteUrl": "https://example.com/" }.',
      },
    ]);
  }
  return parseConfig(text, "sheaf.json");
}

function parseDocuments(
  documents: SourceDocument[],
): Result<ParsedDocument[], Diagnostic[]> {
  return collect(
    documents.map((source) => {
      const tree = parseMarkdown(source);
      if (!tree.ok) return tree;
      const checked = checkLinks(tree.value, source, documents);
      return checked.ok ? ok({ source, tree: checked.value }) : checked;
    }),
  );
}
