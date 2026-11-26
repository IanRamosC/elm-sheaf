import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import type { LanguageRegistration, ThemeRegistration } from "shiki/core";
import type { Config } from "../config/config";
import { isErrno } from "../content/files";
import type { Diagnostic } from "../diagnostics/diagnostic";
import { isObject } from "../json";
import { collect, err, ok, type Result } from "../result";
import { shikiAliases } from "./languages";

/** The grammars and themes a site adds to Shiki's, read from the files `sheaf.json` names. */
export type SiteHighlight = {
  /** By the name code blocks use, which is the key in `highlight.grammars`. */
  grammars: ReadonlyMap<string, LanguageRegistration>;
  /** By the name `highlight.theme` uses, which is the key in `highlight.themes`. */
  themes: ReadonlyMap<string, ThemeRegistration>;
  /** A hash of every file, so highlighted code is cached only as long as they don't change. */
  digest: string;
};

export const noSiteHighlight: SiteHighlight = {
  grammars: new Map(),
  themes: new Map(),
  digest: "",
};

type Kind = "grammars" | "themes";

/** A file's text, which the digest is made from, and what Shiki is given. */
type Loaded<Registration> = { text: string; registration: Registration };

/**
 * Reads the site's grammars and themes, which are TextMate grammars and VS
 * Code themes in JSON, the formats Shiki loads. Each takes the name of its
 * key, whatever the file calls it. Every file that can't be used is reported.
 */
export async function loadSiteHighlight(
  siteRoot: string,
  highlight: Config["highlight"],
): Promise<Result<SiteHighlight, Diagnostic[]>> {
  const [grammars, themes] = await Promise.all([
    loadAll(highlight.grammars, (name, path) =>
      loadGrammar(siteRoot, name, path),
    ),
    loadAll(highlight.themes, (name, path) => loadTheme(siteRoot, name, path)),
  ]);
  if (!grammars.ok || !themes.ok) {
    return err([
      ...(grammars.ok ? [] : grammars.error),
      ...(themes.ok ? [] : themes.error),
    ]);
  }
  const texts = (loaded: Map<string, Loaded<unknown>>) =>
    [...loaded].map(([name, { text }]) => [name, text]);
  return ok({
    grammars: registrations(grammars.value),
    themes: registrations(themes.value),
    digest: createHash("sha256")
      .update(JSON.stringify([texts(grammars.value), texts(themes.value)]))
      .digest("hex"),
  });
}

async function loadAll<Registration>(
  paths: ReadonlyMap<string, string>,
  load: (
    name: string,
    path: string,
  ) => Promise<Result<Loaded<Registration>, Diagnostic>>,
): Promise<Result<Map<string, Loaded<Registration>>, Diagnostic[]>> {
  const loaded = await Promise.all(
    [...paths].map(async ([name, path]) => {
      const result = await load(name, path);
      return result.ok
        ? ok([name, result.value] as const)
        : err([result.error]);
    }),
  );
  const all = collect(loaded);
  return all.ok ? ok(new Map(all.value)) : all;
}

function registrations<Registration>(
  loaded: Map<string, Loaded<Registration>>,
): Map<string, Registration> {
  return new Map(
    [...loaded].map(([name, { registration }]) => [name, registration]),
  );
}

async function loadGrammar(
  siteRoot: string,
  name: string,
  path: string,
): Promise<Result<Loaded<LanguageRegistration>, Diagnostic>> {
  const read = await readJson(siteRoot, "grammars", name, path);
  if (!read.ok) return read;
  const { text, json } = read.value;
  if (!isGrammar(json)) {
    return err(
      badFile(
        "grammars",
        name,
        path,
        'isn\'t a TextMate grammar: it needs "scopeName" and "patterns".',
      ),
    );
  }
  // Shiki's other names for the grammar it replaces become the site's too.
  return ok({
    text,
    registration: { ...json, name, aliases: shikiAliases(name) },
  });
}

async function loadTheme(
  siteRoot: string,
  name: string,
  path: string,
): Promise<Result<Loaded<ThemeRegistration>, Diagnostic>> {
  const read = await readJson(siteRoot, "themes", name, path);
  if (!read.ok) return read;
  const { text, json } = read.value;
  if (!isTheme(json)) {
    return err(
      badFile(
        "themes",
        name,
        path,
        'isn\'t a VS Code theme: it needs "tokenColors" or "colors".',
      ),
    );
  }
  return ok({ text, registration: { ...json, name } });
}

async function readJson(
  siteRoot: string,
  kind: Kind,
  name: string,
  path: string,
): Promise<Result<{ text: string; json: unknown }, Diagnostic>> {
  let text: string;
  try {
    text = await readFile(resolve(siteRoot, path), "utf8");
  } catch (error) {
    if (!isErrno(error)) throw error;
    return err(
      badFile(
        kind,
        name,
        path,
        error.code === "ENOENT"
          ? "doesn't exist."
          : `can't be read (${error.code}).`,
      ),
    );
  }
  try {
    return ok({ text, json: JSON.parse(text) });
  } catch (error) {
    const reason = error instanceof Error ? error.message : String(error);
    return err(badFile(kind, name, path, `isn't valid JSON: ${reason}`));
  }
}

/** `problem` finishes the sentence that names the key and its file. */
function badFile(
  kind: Kind,
  name: string,
  path: string,
  problem: string,
): Diagnostic {
  return {
    severity: "error",
    title: "BAD CONFIG",
    message: `"highlight.${kind}.${name}" names \`${path}\`, which ${problem}`,
    sourcePath: "sheaf.json",
    hint: "Paths in sheaf.json are relative to the site's folder.",
  };
}

/**
 * Checks what Shiki needs to load a grammar. The rest of the file is
 * TextMate's to interpret, as it is for Shiki's own grammars.
 */
function isGrammar(json: unknown): json is Omit<LanguageRegistration, "name"> {
  return (
    isObject(json) &&
    typeof json.scopeName === "string" &&
    Array.isArray(json.patterns)
  );
}

function isTheme(json: unknown): json is Omit<ThemeRegistration, "name"> {
  return (
    isObject(json) && (Array.isArray(json.tokenColors) || isObject(json.colors))
  );
}
