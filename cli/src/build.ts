import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { type Config, parseConfig } from "./config/config";
import type { SourceDocument } from "./content/document";
import {
  type ContentFiles,
  isErrno,
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
import { checkElmPackage } from "./elm/package-version";
import {
  encodeRequest,
  type ParsedDocument,
  type Response,
} from "./elm/protocol";
import { runElm } from "./elm/run";
import { staticClashes } from "./emit/clashes";
import { atomFeed, rssFeed } from "./emit/feeds";
import { providesRobots, robotsTxt } from "./emit/robots";
import { sitemapXml } from "./emit/sitemap";
import { listStaticFiles } from "./emit/static";
import { type OutputFile, writeGenerated, writeSite } from "./emit/write";
import { loadHighlightCache, saveHighlightCache } from "./highlight/cache";
import {
  createCodeHighlighter,
  highlightCode,
  languagesIn,
} from "./highlight/highlight";
import { loadSiteHighlight, type SiteHighlight } from "./highlight/site";
import { imageOutputs } from "./images/emit";
import {
  type ImageFile,
  pruneImageCache,
  resolveImages,
} from "./images/resolve";
import { checkLinks } from "./markdown/links";
import { parseMarkdown } from "./markdown/parse";
import { collect, err, ok, type Result } from "./result";

export type BuildOptions = {
  mode: BuildMode;
  /** Decides which dated documents are not yet published. */
  now: Date;
  /** The absolute folder the site is written to; `undefined` is `sheaf check`, which writes no site. */
  output: string | undefined;
  /** Whether Elm compiles with `--optimize`, which rejects `Debug` calls. */
  optimize: boolean;
  /** Replaces the `siteUrl` of `sheaf.json`. */
  siteUrl?: string;
  /** Receives what the Elm worker logs, as it logs it. */
  log: (line: string) => void;
};

export type BuildSuccess = {
  /** The pages Elm rendered, not counting redirects. */
  pages: number;
  redirects: number;
  warnings: Diagnostic[];
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
  const config = await readConfig(siteRoot, options.siteUrl);
  if (!config.ok) return config;
  // The files sheaf.json names are part of the config, so they are read first.
  const siteHighlight = await loadSiteHighlight(
    siteRoot,
    config.value.highlight,
  );
  if (!siteHighlight.ok) return siteHighlight;

  const elmPackage = await readElmPackage(siteRoot);
  if (!elmPackage.ok) return elmPackage;

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
    siteHighlight.value,
    parsed.value,
  );
  if (!highlighted.ok) return highlighted;

  const imaged = await resolveDocumentImages(
    siteRoot,
    config.value,
    highlighted.value.documents,
  );
  if (!imaged.ok) return imaged;

  const staticFiles = await listStaticFiles(siteRoot);
  if (!staticFiles.ok) return staticFiles;

  const elm = await findElm(siteRoot);
  if (!elm.ok) return elm;
  const compiled = await compileElm(siteRoot, {
    elm: elm.value,
    optimize: options.optimize,
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
  const ran = await runElm(compiled.value, request, options.log);
  if (!ran.ok) return ran;

  const response = ran.value;
  const { pages, diagnostics } = response;
  if (diagnostics.some(({ severity }) => severity === "error")) {
    return err(diagnostics);
  }
  const outputs = [
    ...outputFiles(response, config.value),
    ...imageOutputs(imaged.value.published),
  ];
  // A default: the site's own file, or a route's, takes its place unreported.
  if (
    !providesRobots([...outputs, ...staticFiles.value].map(({ path }) => path))
  ) {
    outputs.push(robotsFile(config.value));
  }
  const clashes = staticClashes(outputs, staticFiles.value);
  if (clashes.length > 0) return err(clashes);
  if (options.output !== undefined) {
    await writeSite(options.output, outputs, staticFiles.value);
  }
  const redirects = pages.filter(({ aliasOf }) => aliasOf !== undefined);
  return ok({
    pages: pages.length - redirects.length,
    redirects: redirects.length,
    warnings: [...highlighted.value.warnings, ...diagnostics],
  });
}

/** The origin plus base path; `siteUrl.href` may lack the trailing slash that relative paths need. */
function siteBase(config: Config): string {
  return config.siteUrl.origin + config.basePath;
}

function robotsFile(config: Config): OutputFile {
  return {
    kind: "text",
    path: "robots.txt",
    content: robotsTxt(new URL("sitemap.xml", siteBase(config)).href),
  };
}

function outputFiles(response: Response, config: Config): OutputFile[] {
  const site = siteBase(config);
  const files: OutputFile[] = response.pages.map(({ path, html, aliasOf }) => ({
    kind: "text",
    path,
    content: html,
    ...(aliasOf !== undefined && { aliasOf }),
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
        content: rssFeed(feed, render(feed.rss), response.site),
      },
      {
        kind: "text",
        path: feed.atom,
        content: atomFeed(feed, render(feed.atom), response.site),
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
  siteUrl: string | undefined,
): Promise<Result<Config, Diagnostic[]>> {
  let text: string;
  try {
    text = await readFile(join(siteRoot, "sheaf.json"), "utf8");
  } catch (error) {
    if (!isErrno(error) || error.code !== "ENOENT") throw error;
    return err([
      {
        severity: "error",
        title: "NO SHEAF.JSON",
        message: `There is no sheaf.json in ${siteRoot}, so this does not look like a Sheaf site.`,
        hint: 'Run this command in your site\'s folder, or create sheaf.json with { "siteUrl": "https://example.com/" }.',
      },
    ]);
  }
  return parseConfig(text, "sheaf.json", {
    ...(siteUrl === undefined ? {} : { siteUrl }),
  });
}

async function readElmPackage(
  siteRoot: string,
): Promise<Result<void, Diagnostic[]>> {
  let text: string;
  try {
    text = await readFile(join(siteRoot, "elm.json"), "utf8");
  } catch (error) {
    if (!isErrno(error)) throw error;
    return err([
      {
        severity: "error",
        title: "BAD ELM JSON",
        message: `elm.json in ${siteRoot} could not be read: ${error.code}.`,
      },
    ]);
  }
  // `resolve` keeps the absolute directories that `init --local` writes.
  return checkElmPackage(text, (directory) =>
    existsSync(resolve(siteRoot, directory, "Sheaf.elm")),
  );
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
  site: SiteHighlight,
  documents: ParsedDocument[],
): Promise<
  Result<{ documents: ParsedDocument[]; warnings: Diagnostic[] }, Diagnostic[]>
> {
  const cache = await loadHighlightCache(siteRoot);
  using highlighter = await createCodeHighlighter(
    config.highlight.theme,
    languagesIn(documents.map(({ tree }) => tree)),
    cache,
    site,
  );
  const highlighted = collect(
    documents.map(({ source, tree }) => {
      const result = highlightCode(tree, source, highlighter);
      return result.ok ? ok({ source, tree: result.value }) : result;
    }),
  );
  if (!highlighted.ok) return highlighted;
  const saved = await saveHighlightCache(siteRoot, cache);
  return ok({
    documents: highlighted.value,
    warnings: saved.ok ? [] : [saved.error],
  });
}

/**
 * Resolves the images of every document, drafts included, so their errors are
 * reported in every mode. Only the files of documents in this build's output
 * are published, so a draft's images never reach a production `dist/`. The
 * cache keeps the files of all of them and drops the rest.
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
        imageFiles,
        published: source.excluded ? [] : imageFiles,
      });
    }),
  );
  const resolved = collect(results);
  if (!resolved.ok) return resolved;
  await pruneImageCache(
    siteRoot,
    resolved.value.flatMap(({ imageFiles }) => imageFiles),
  );
  return ok({
    documents: resolved.value.map(({ document }) => document),
    published: resolved.value.flatMap(({ published }) => published),
  });
}
