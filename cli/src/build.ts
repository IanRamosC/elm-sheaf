import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { type Config, parseConfig } from "./config/config";
import type { SourceDocument } from "./content/document";
import {
  type ContentFiles,
  listContentFiles,
  listFiles,
} from "./content/files";
import {
  type BuildMode,
  loadContent,
  readCollectionNames,
  readContentFiles,
} from "./content/load";
import { slugTable } from "./content/slug";
import type { Diagnostic } from "./diagnostics/diagnostic";
import { compileElm, findElm } from "./elm/compile";
import { generateElm } from "./elm/generate";
import { assignValueNames } from "./elm/names";
import {
  encodeRequest,
  type ParsedDocument,
  type Response,
} from "./elm/protocol";
import { runElm } from "./elm/run";
import { atomFeed, rssFeed } from "./emit/feeds";
import { sitemapXml } from "./emit/sitemap";
import { listStaticFiles } from "./emit/static";
import { type OutputFile, writeGenerated, writeSite } from "./emit/write";
import { loadHighlightCache, saveHighlightCache } from "./highlight/cache";
import {
  createCodeHighlighter,
  highlightCode,
  languagesIn,
} from "./highlight/highlight";
import { imageOutputs } from "./images/emit";
import { type ImageFile, resolveImages } from "./images/resolve";
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
  const collections = await readCollectionNames(siteRoot);
  const documents = loadContent(
    files,
    config.value,
    options.now,
    options.mode,
    collections,
  );
  if (!documents.ok) return documents;

  const names = assignValueNames(documents.value);
  if (!names.ok) return names;

  // Generated before the checks that follow, so the language server has the
  // typed references while the author fixes Markdown errors.
  await writeGenerated(
    siteRoot,
    generateElm(collections, documents.value, names.value),
  );

  const parsed = parseDocuments(
    documents.value,
    await listContentFiles(siteRoot),
  );
  if (!parsed.ok) return parsed;

  const highlighted = await highlightDocuments(
    siteRoot,
    config.value,
    parsed.value,
  );
  if (!highlighted.ok) return highlighted;

  const imaged = await resolveDocumentImages(
    siteRoot,
    config.value,
    highlighted.value,
  );
  if (!imaged.ok) return imaged;

  const staticFiles = await listStaticFiles(siteRoot);
  if (!staticFiles.ok) return staticFiles;

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
    imaged.value.documents,
    slugTable(documents.value),
  );
  const ran = await runElm(compiled.value, request);
  if (!ran.ok) return ran;

  const { response } = ran.value;
  const { pages, diagnostics } = response;
  if (diagnostics.some(({ severity }) => severity === "error")) {
    return err(diagnostics);
  }
  if (options.write) {
    await writeSite(
      siteRoot,
      [
        ...outputFiles(response, config.value, options.now),
        ...imageOutputs(imaged.value.published),
      ],
      staticFiles.value,
    );
  }
  return ok({
    pages: pages.length,
    warnings: diagnostics,
    output: ran.value.output,
  });
}

function outputFiles(
  response: Response,
  config: Config,
  now: Date,
): OutputFile[] {
  // `siteUrl.href` may lack the trailing slash that relative feed paths need.
  const site = config.siteUrl.origin + config.basePath;
  const files: OutputFile[] = response.pages.map(({ path, html }) => ({
    kind: "text",
    path,
    content: html,
  }));
  for (const feed of response.feeds) {
    const render = (path: string) => ({
      site,
      feed: new URL(path, site).href,
    });
    files.push(
      {
        kind: "text",
        path: feed.rss,
        content: rssFeed(feed, render(feed.rss), response.site, now),
      },
      {
        kind: "text",
        path: feed.atom,
        content: atomFeed(feed, render(feed.atom), response.site, now),
      },
    );
  }
  files.push({
    kind: "text",
    path: "sitemap.xml",
    content: sitemapXml(response.sitemap),
  });
  return files;
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
  files: ContentFiles,
): Result<ParsedDocument[], Diagnostic[]> {
  return collect(
    documents.map((source) => {
      const tree = parseMarkdown(source);
      if (!tree.ok) return tree;
      const checked = checkLinks(tree.value, source, documents, files);
      return checked.ok ? ok({ source, tree: checked.value }) : checked;
    }),
  );
}

/**
 * Highlights the code of every document, drafts included, so their errors are
 * reported in every mode. Only a build with no unknown language saves the
 * cache, because a failed one has not asked for every entry the site uses.
 */
async function highlightDocuments(
  siteRoot: string,
  config: Config,
  documents: ParsedDocument[],
): Promise<Result<ParsedDocument[], Diagnostic[]>> {
  const cache = await loadHighlightCache(siteRoot);
  using highlighter = await createCodeHighlighter(
    config.highlight,
    languagesIn(documents.map(({ tree }) => tree)),
    cache,
  );
  const highlighted = collect(
    documents.map(({ source, tree }) => {
      const result = highlightCode(tree, source, highlighter);
      return result.ok ? ok({ source, tree: result.value }) : result;
    }),
  );
  if (highlighted.ok) await saveHighlightCache(siteRoot, cache);
  return highlighted;
}

/**
 * Resolves the images of every document, drafts included, so their errors are
 * reported in every mode. Only the files of documents in this build's output
 * are published, so a draft's images never reach a production `dist/`.
 */
async function resolveDocumentImages(
  siteRoot: string,
  config: Config,
  documents: ParsedDocument[],
): Promise<
  Result<{ documents: ParsedDocument[]; published: ImageFile[] }, Diagnostic[]>
> {
  const files = await listFiles(siteRoot, "content", "static");
  const results = await Promise.all(
    documents.map(async ({ source, tree }) => {
      const resolved = await resolveImages(
        tree,
        source,
        siteRoot,
        config,
        files,
      );
      if (!resolved.ok) return resolved;
      const { image, files: imageFiles } = resolved.value;
      return ok({
        document: {
          source,
          tree: resolved.value.tree,
          ...(image && { image }),
        },
        published: source.excluded ? [] : imageFiles,
      });
    }),
  );
  const resolved = collect(results);
  if (!resolved.ok) return resolved;
  return ok({
    documents: resolved.value.map(({ document }) => document),
    published: resolved.value.flatMap(({ published }) => published),
  });
}
