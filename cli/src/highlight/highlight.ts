import { createHash } from "node:crypto";
import {
  createHighlighterCore,
  isSpecialLang,
  stringifyTokenStyle,
} from "shiki/core";
import { createJavaScriptRegexEngine } from "shiki/engine/javascript";
import { type BundledLanguage, bundledLanguages } from "shiki/langs";
import shikiPackage from "shiki/package.json";
import { type BundledTheme, bundledThemes } from "shiki/themes";
import type { Config } from "../config/config";
import type { SourceDocument } from "../content/document";
import type { Diagnostic } from "../diagnostics/diagnostic";
import type { Highlight, Node } from "../markdown/tree";
import { collect, err, ok, type Result } from "../result";
import { suggestions } from "../suggest";
import type { HighlightCache } from "./cache";
import { excludedGrammar, excludedHint } from "./excluded";
import { noSiteHighlight, type SiteHighlight } from "./site";

/** Shiki's name for code with no highlighting, used for a block with no language. */
const PLAIN = "text";

/**
 * Highlights code blocks with the site's themes, through the cache. Declare it
 * with `using`: Shiki keeps every highlighter alive until it is disposed, and
 * `sheaf dev` builds many times.
 */
export type CodeHighlighter = Disposable & {
  /** Whether Sheaf can highlight a block marked `language`. */
  knows: (language: string) => boolean;
  /** The names a code block can use, for "did you mean" hints. */
  languages: () => string[];
  highlight: (code: string, language: string) => Highlight;
};

/**
 * Loads the themes and the grammars of `languages`, once for the whole build.
 * Names Shiki doesn't know are skipped here and reported by `highlightCode`.
 * The site's own grammars and themes replace Shiki's of the same name.
 */
export async function createCodeHighlighter(
  themes: Config["highlight"]["theme"],
  languages: string[],
  cache: HighlightCache,
  site: SiteHighlight = noSiteHighlight,
): Promise<CodeHighlighter> {
  const theme = (name: string) => site.themes.get(name) ?? bundledTheme(name);
  const shiki = await createHighlighterCore({
    // The JavaScript engine needs no WebAssembly and gives the same tokens on
    // every machine.
    engine: createJavaScriptRegexEngine(),
    themes: [theme(themes.light), theme(themes.dark)],
    // The site's grammars come last: of two with one name, Shiki keeps the later.
    langs: [
      ...languages
        .filter((language) => !site.grammars.has(language))
        .filter(isIncludedLanguage)
        .map((language) => bundledLanguages[language]),
      ...site.grammars.values(),
    ],
  });

  return {
    [Symbol.dispose]: () => shiki.dispose(),
    knows: (language) =>
      isSpecialLang(language) ||
      site.grammars.has(language) ||
      isIncludedLanguage(language),
    languages: () => [
      ...site.grammars.keys(),
      ...Object.keys(bundledLanguages).filter(isIncludedLanguage),
    ],
    highlight: (code, language) =>
      cache.get(cacheKey(themes, site.digest, code, language), () => {
        const { tokens, fg, bg } = shiki.codeToTokens(code, {
          lang: language,
          themes: { light: themes.light, dark: themes.dark },
        });
        return {
          // As Shiki's own `codeToHtml` writes it, so its documented CSS applies.
          style: `background-color:${bg};color:${fg}`,
          // Shiki gives an empty block one empty line, but it has none.
          lines:
            code === ""
              ? []
              : tokens.map((line) =>
                  line.map(({ content, htmlStyle }) => ({
                    content,
                    style: htmlStyle ? stringifyTokenStyle(htmlStyle) : "",
                  })),
                ),
        };
      }),
  };
}

/** Every language that a code block in `trees` is marked with, once each. */
export function languagesIn(trees: Node[]): string[] {
  const languages = new Set<string>();
  const visit = (node: Node): void => {
    if (node.type === "code" && node.lang !== undefined) {
      languages.add(node.lang);
    }
    if ("children" in node) node.children.forEach(visit);
  };
  trees.forEach(visit);
  return [...languages];
}

/**
 * Gives every code block in `tree` its highlight. A block with no language is
 * plain text; one marked with a language Shiki doesn't know is an error, so a
 * typo never quietly turns into plain output.
 */
export function highlightCode(
  tree: Node,
  document: SourceDocument,
  highlighter: CodeHighlighter,
): Result<Node, Diagnostic[]> {
  if (tree.type === "code") {
    const language = tree.lang ?? PLAIN;
    if (!highlighter.knows(language)) {
      return err([unknownLanguage(tree, language, document, highlighter)]);
    }
    return ok({
      ...tree,
      highlight: highlighter.highlight(tree.value, language),
    });
  }
  if (!("children" in tree)) return ok(tree);
  const children = collect(
    tree.children.map((child) => highlightCode(child, document, highlighter)),
  );
  return children.ok ? ok({ ...tree, children: children.value }) : children;
}

function unknownLanguage(
  block: Node,
  language: string,
  document: SourceDocument,
  highlighter: CodeHighlighter,
): Diagnostic {
  return {
    severity: "error",
    title: "UNKNOWN LANGUAGE",
    message: `This code block is marked as \`${language}\`, which Sheaf can't highlight.`,
    sourcePath: document.sourcePath,
    span: block.position,
    hint: unknownLanguageHint(language, highlighter.languages()),
  };
}

function unknownLanguageHint(language: string, known: string[]): string {
  const excluded = excludedGrammar(language);
  if (excluded !== undefined) return excludedHint("grammar", excluded);
  const [closest] = suggestions(language, known, 1);
  const plainHint = `Use \`${PLAIN}\` for a block without highlighting.`;
  return closest === undefined
    ? plainHint
    : `Did you mean \`${closest}\`? ${plainHint}`;
}

/**
 * Anything that changes the tokens is part of the key: Shiki's version,
 * because a new release may tokenize the same code differently, and the
 * site's own grammar and theme files.
 */
function cacheKey(
  themes: Config["highlight"]["theme"],
  siteDigest: string,
  code: string,
  language: string,
): string {
  return createHash("sha256")
    .update(
      JSON.stringify([
        shikiPackage.version,
        siteDigest,
        themes.light,
        themes.dark,
        language,
        code,
      ]),
    )
    .digest("hex");
}

/** Whether Shiki has a grammar for `name` and Sheaf includes it. */
function isIncludedLanguage(name: string): name is BundledLanguage {
  return (
    Object.hasOwn(bundledLanguages, name) && excludedGrammar(name) === undefined
  );
}

function bundledTheme(name: string) {
  if (!isBundledTheme(name)) {
    throw new Error(
      `${name} is not a Shiki theme, so the config should have been rejected`,
    );
  }
  return bundledThemes[name];
}

function isBundledTheme(name: string): name is BundledTheme {
  return Object.hasOwn(bundledThemes, name);
}
