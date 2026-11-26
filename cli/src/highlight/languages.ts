import { bundledLanguagesInfo } from "shiki/langs";

/** Shiki's other names for its grammar `id`, such as `js` for `javascript`. */
export function shikiAliases(id: string): string[] {
  return bundledLanguagesInfo.find((info) => info.id === id)?.aliases ?? [];
}

/** The Shiki grammar that `name` is another name for, when it is only an alias. */
export function aliasedGrammar(name: string): string | undefined {
  return bundledLanguagesInfo.find(({ aliases = [] }) => aliases.includes(name))
    ?.id;
}
