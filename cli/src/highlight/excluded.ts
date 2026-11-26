import { bundledLanguagesInfo } from "shiki/langs";

/** GPL-3.0, which Sheaf's BSD-3-Clause binaries can't carry. */
export const EXCLUDED_GRAMMARS: readonly string[] = [
  "ada",
  "gnuplot",
  "nginx",
  "org",
  "racket",
];

/** GPL-3.0, which Sheaf's BSD-3-Clause binaries can't carry. */
export const EXCLUDED_THEMES: readonly string[] = ["aurora-x"];

/** Each name a code block can use for an excluded grammar, aliases included, with the grammar's own name. */
const excludedLanguages = new Map(
  bundledLanguagesInfo
    .filter(({ id }) => EXCLUDED_GRAMMARS.includes(id))
    .flatMap(({ id, aliases = [] }) =>
      [id, ...aliases].map((name) => [name, id] as const),
    ),
);

/** The excluded grammar that `language` names, if it names one. */
export function excludedGrammar(language: string): string | undefined {
  return excludedLanguages.get(language);
}

/** Every name of an excluded grammar, aliases included. */
export function excludedLanguageNames(): string[] {
  return [...excludedLanguages.keys()];
}

export function isExcludedTheme(name: string): boolean {
  return EXCLUDED_THEMES.includes(name);
}

/** Why a grammar or theme Shiki has is missing, and how a site can add it. */
export function excludedHint(kind: "grammar" | "theme", name: string): string {
  const key = kind === "grammar" ? "highlight.grammars" : "highlight.themes";
  return `Shiki's ${name} ${kind} is GPL-3.0, so Sheaf doesn't include it. Add it to your site with "${key}" in sheaf.json.`;
}
