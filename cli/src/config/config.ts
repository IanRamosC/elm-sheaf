import { isSpecialLang } from "shiki/core";
import { bundledThemes } from "shiki/themes";
import type { Diagnostic } from "../diagnostics/diagnostic";
import { excludedHint, isExcludedTheme } from "../highlight/excluded";
import { aliasedGrammar } from "../highlight/languages";
import { isObject } from "../json";
import { err, ok, type Result } from "../result";
import { suggestions } from "../suggest";

/** The settings the host needs before any Elm code runs, read from `sheaf.json`. */
export type Config = {
  siteUrl: URL;
  /** The path every generated URL is served under; always starts and ends with `/`. */
  basePath: string;
  /** IANA timezone name that decides when a date-only post counts as published. */
  timezone: string;
  highlight: {
    /** The themes code is highlighted with: Shiki's, or the site's own. */
    theme: { light: string; dark: string };
    /** The site's own grammars and themes, by name, as paths relative to the site root. */
    grammars: ReadonlyMap<string, string>;
    themes: ReadonlyMap<string, string>;
  };
  /** The widths local images are resized to, and the formats written besides the original's. */
  images: { widths: number[]; formats: ImageFormat[] };
};

/** A format Sheaf writes image variants in, besides each image's own. */
export type ImageFormat = "webp";

const knownKeys = ["siteUrl", "timezone", "highlight", "images"];

const defaultTimezone = "UTC";

// GitHub's themes whose token colours meet WCAG AA contrast; `github-light`
// and `github-dark` have some that don't.
const defaultThemes: Config["highlight"]["theme"] = {
  light: "github-light-default",
  dark: "github-dark-default",
};

const defaultImages: Config["images"] = {
  widths: [480, 960, 1600],
  formats: ["webp"],
};

/** A problem with one key, before it is located in `sheaf.json`. */
type Problem = { message: string; hint?: string };

/**
 * Parses the text of `sheaf.json`, reporting every problem found in it at
 * once. A `siteUrl` override, from `--site-url`, replaces the one in the file.
 */
export function parseConfig(
  json: string,
  sourcePath: string,
  overrides: { siteUrl?: string } = {},
): Result<Config, Diagnostic[]> {
  const badConfig = (
    message: string,
    hint?: string,
    inFile = true,
  ): Diagnostic => ({
    severity: "error",
    title: "BAD CONFIG",
    message,
    ...(inFile ? { sourcePath } : {}),
    ...(hint === undefined ? {} : { hint }),
  });

  let parsed: unknown;
  try {
    parsed = JSON.parse(json);
  } catch (error) {
    const reason = error instanceof Error ? error.message : String(error);
    return err([badConfig(`This file is not valid JSON: ${reason}`)]);
  }
  if (!isObject(parsed)) {
    return err([
      badConfig("The top level of this file must be a JSON object."),
    ]);
  }
  const fields = parsed;

  const problems: Diagnostic[] = unknownKeys(fields, knownKeys, "").map(
    ({ message, hint }) => badConfig(message, hint),
  );

  const siteUrl =
    overrides.siteUrl === undefined
      ? parseSiteUrl(fields.siteUrl)
      : parseFullUrl(overrides.siteUrl, `--site-url "${overrides.siteUrl}"`);
  if (!siteUrl.ok) {
    // The flag is not in the file, so pointing at the file would mislead.
    problems.push(
      badConfig(
        siteUrl.error.message,
        siteUrl.error.hint,
        overrides.siteUrl === undefined,
      ),
    );
  }

  const timezone = parseTimezone(fields.timezone);
  if (!timezone.ok) problems.push(badConfig(timezone.error));

  const highlight = parseHighlight(fields.highlight);
  if (!highlight.ok) {
    problems.push(
      ...highlight.error.map(({ message, hint }) => badConfig(message, hint)),
    );
  }

  const images = parseImages(fields.images);
  if (!images.ok) {
    problems.push(
      ...images.error.map(({ message, hint }) => badConfig(message, hint)),
    );
  }

  if (
    !siteUrl.ok ||
    !timezone.ok ||
    !highlight.ok ||
    !images.ok ||
    problems.length > 0
  ) {
    return err(problems);
  }

  return ok({
    siteUrl: siteUrl.value,
    basePath: basePathOf(siteUrl.value),
    timezone: timezone.value,
    highlight: highlight.value,
    images: images.value,
  });
}

/** `{ "widths": [480, 960, 1600], "formats": ["webp"] }`, where both are optional. */
function parseImages(value: unknown): Result<Config["images"], Problem[]> {
  if (value === undefined) return ok(defaultImages);
  if (!isObject(value)) {
    return err([{ message: '"images" must be an object.' }]);
  }
  const problems = unknownKeys(value, ["widths", "formats"], "images.");
  const widths = parseWidths(value.widths);
  const formats = parseFormats(value.formats);
  if (!widths.ok) problems.push(widths.error);
  if (!formats.ok) problems.push(...formats.error);
  if (!widths.ok || !formats.ok || problems.length > 0) return err(problems);
  return ok({ widths: widths.value, formats: formats.value });
}

function parseWidths(value: unknown): Result<number[], Problem> {
  if (value === undefined) return ok(defaultImages.widths);
  const isWidth = (width: unknown): width is number =>
    typeof width === "number" && Number.isInteger(width) && width > 0;
  if (Array.isArray(value) && value.length > 0 && value.every(isWidth)) {
    return ok(value);
  }
  return err({
    message: '"images.widths" must be a non-empty list of widths in pixels.',
    hint: 'Use whole numbers above 0, such as "widths": [480, 960, 1600].',
  });
}

const FORMATS_HINT = 'Use "formats": ["webp"].';

function parseFormats(value: unknown): Result<ImageFormat[], Problem[]> {
  if (value === undefined) return ok(defaultImages.formats);
  if (!Array.isArray(value)) {
    return err([
      { message: '"images.formats" must be a list.', hint: FORMATS_HINT },
    ]);
  }
  const formats: ImageFormat[] = [];
  const problems: Problem[] = [];
  for (const format of value) {
    if (format === "webp") {
      if (!formats.includes(format)) formats.push(format);
    } else if (format === "avif") {
      problems.push({
        message: '"images.formats" asks for AVIF.',
        hint: `Sheaf writes WebP variants only: Bun's image encoder can't write AVIF on Linux, where most sites are built. ${FORMATS_HINT}`,
      });
    } else {
      problems.push({
        message: `${JSON.stringify(format)} in "images.formats" is not an image format Sheaf writes.`,
        hint: FORMATS_HINT,
      });
    }
  }
  return problems.length > 0 ? err(problems) : ok(formats);
}

/**
 * `{ "theme": { "light": …, "dark": … }, "grammars": {…}, "themes": {…} }`,
 * where every part is optional. The files are read later, by the build.
 */
function parseHighlight(
  value: unknown,
): Result<Config["highlight"], Problem[]> {
  if (value === undefined) {
    return ok({ theme: defaultThemes, grammars: new Map(), themes: new Map() });
  }
  if (!isObject(value)) {
    return err([{ message: '"highlight" must be an object.' }]);
  }
  const problems = unknownKeys(
    value,
    ["theme", "grammars", "themes"],
    "highlight.",
  );
  const grammars = parsePaths(value.grammars, "grammars");
  const themes = parsePaths(value.themes, "themes");
  if (!grammars.ok) problems.push(...grammars.error);
  if (!themes.ok) problems.push(...themes.error);
  const theme = parseThemes(value.theme, themes.ok ? themes.value : new Map());
  if (!theme.ok) problems.push(...theme.error);
  if (!grammars.ok || !themes.ok || !theme.ok || problems.length > 0) {
    return err(problems);
  }
  return ok({
    theme: theme.value,
    grammars: grammars.value,
    themes: themes.value,
  });
}

/** `"grammars"` or `"themes"`: names mapped to the paths of their files. */
function parsePaths(
  value: unknown,
  key: "grammars" | "themes",
): Result<Map<string, string>, Problem[]> {
  if (value === undefined) return ok(new Map());
  if (!isObject(value)) {
    const example =
      key === "grammars"
        ? '"grammars": { "nginx": "highlight/nginx.tmLanguage.json" }'
        : '"themes": { "my-theme": "highlight/my-theme.json" }';
    return err([
      {
        message: `"highlight.${key}" must be an object.`,
        hint: `Map each name to a file in your site, such as ${example}.`,
      },
    ]);
  }
  const paths = new Map<string, string>();
  const problems: Problem[] = [];
  for (const [name, path] of Object.entries(value)) {
    const badName = key === "grammars" ? grammarNameProblem(name) : undefined;
    if (badName !== undefined) {
      problems.push(badName);
    } else if (typeof path === "string") {
      paths.set(name, path);
    } else {
      problems.push({
        message: `"highlight.${key}.${name}" must be a string.`,
        hint: "Give the path of a JSON file, relative to the site's folder.",
      });
    }
  }
  return problems.length > 0 ? err(problems) : ok(paths);
}

/**
 * A site's grammar replaces Shiki's grammar of that name under all of its
 * names, so it must take the grammar's own name rather than one of the others.
 */
function grammarNameProblem(name: string): Problem | undefined {
  if (isSpecialLang(name)) {
    return {
      message: `"highlight.grammars.${name}" uses \`${name}\`, which Shiki keeps for code without highlighting.`,
      hint: "Give the grammar another name.",
    };
  }
  const grammar = aliasedGrammar(name);
  if (grammar === undefined) return undefined;
  return {
    message: `"highlight.grammars.${name}" uses \`${name}\`, which is another name for Shiki's \`${grammar}\` grammar.`,
    hint: `Name the grammar "${grammar}". It then replaces Shiki's under all of its names, \`${name}\` included.`,
  };
}

function parseThemes(
  value: unknown,
  siteThemes: ReadonlyMap<string, string>,
): Result<Config["highlight"]["theme"], Problem[]> {
  const theme = value ?? {};
  if (!isObject(theme)) {
    return err([{ message: '"highlight.theme" must be an object.' }]);
  }
  const problems = unknownKeys(theme, ["light", "dark"], "highlight.theme.");
  const light = parseTheme(theme.light, "light", siteThemes);
  const dark = parseTheme(theme.dark, "dark", siteThemes);
  if (!light.ok) problems.push(light.error);
  if (!dark.ok) problems.push(dark.error);
  if (!light.ok || !dark.ok || problems.length > 0) return err(problems);
  return ok({ light: light.value, dark: dark.value });
}

function parseTheme(
  value: unknown,
  variant: keyof Config["highlight"]["theme"],
  siteThemes: ReadonlyMap<string, string>,
): Result<string, Problem> {
  if (value === undefined) return ok(defaultThemes[variant]);
  if (typeof value !== "string") {
    return err({ message: `"highlight.theme.${variant}" must be a string.` });
  }
  if (siteThemes.has(value) || isIncludedTheme(value)) return ok(value);
  if (isExcludedTheme(value)) {
    return err({
      message: `The ${variant} theme "${value}" is not a theme Sheaf can use.`,
      hint: excludedHint("theme", value),
    });
  }
  const [closest] = suggestions(
    value,
    [
      ...siteThemes.keys(),
      ...Object.keys(bundledThemes).filter(isIncludedTheme),
    ],
    1,
  );
  return err({
    message: `The ${variant} theme "${value}" is not one of Shiki's themes${siteThemes.size > 0 ? " or the site's" : ""}.`,
    hint:
      closest === undefined
        ? "The themes are listed at https://shiki.style/themes."
        : `Did you mean "${closest}"?`,
  });
}

/** Whether Shiki has the theme `name` and Sheaf includes it. */
function isIncludedTheme(name: string): boolean {
  return Object.hasOwn(bundledThemes, name) && !isExcludedTheme(name);
}

function unknownKeys(
  fields: Record<string, unknown>,
  known: string[],
  prefix: string,
): Problem[] {
  return Object.keys(fields)
    .filter((key) => !known.includes(key))
    .map((key) => {
      const [closest] = suggestions(key, known, 1);
      return {
        message: `I do not know the key "${prefix}${key}".`,
        ...(closest === undefined
          ? {}
          : { hint: `Did you mean "${closest}"?` }),
      };
    });
}

const FULL_URL_HINT = "Use a full URL such as https://example.com/";

function parseSiteUrl(
  value: unknown,
): Result<URL, { message: string; hint?: string }> {
  if (value === undefined) {
    return err({
      message: 'The required key "siteUrl" is missing.',
      hint: FULL_URL_HINT,
    });
  }
  if (typeof value !== "string") {
    return err({ message: '"siteUrl" must be a string.', hint: FULL_URL_HINT });
  }
  return parseFullUrl(value, `"${value}"`);
}

/** `subject` is how messages refer to the value: the quoted text, or the flag it came from. */
function parseFullUrl(
  value: string,
  subject: string,
): Result<URL, { message: string; hint?: string }> {
  const notAFullUrl = err({
    message: `${subject} is not a full URL.`,
    hint: FULL_URL_HINT,
  });
  try {
    const url = new URL(value);
    // "localhost:3000" parses with "localhost:" as its scheme, so the scheme
    // has to be checked for a base path to exist at all.
    if (url.protocol !== "http:" && url.protocol !== "https:") {
      return notAFullUrl;
    }
    if (url.search !== "" || url.hash !== "") {
      return err({
        message: `${subject} has a query or a fragment.`,
        hint: 'Write the site\'s address without "?" or "#", such as https://example.com/blog/.',
      });
    }
    return ok(url);
  } catch {
    return notAFullUrl;
  }
}

function parseTimezone(value: unknown): Result<string, string> {
  if (value === undefined) return ok(defaultTimezone);
  if (typeof value !== "string") return err('"timezone" must be a string.');
  try {
    new Intl.DateTimeFormat("en", { timeZone: value });
    return ok(value);
  } catch (error) {
    if (error instanceof RangeError) {
      return err(
        `"${value}" is not an IANA timezone name such as Europe/Lisbon.`,
      );
    }
    throw error;
  }
}

function basePathOf(siteUrl: URL): string {
  return siteUrl.pathname.endsWith("/")
    ? siteUrl.pathname
    : `${siteUrl.pathname}/`;
}
