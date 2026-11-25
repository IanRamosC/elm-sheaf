import { bundledThemes } from "shiki/themes";
import type { Diagnostic } from "../diagnostics/diagnostic";
import { err, ok, type Result } from "../result";
import { suggestions } from "../suggest";

/** The settings the host needs before any Elm code runs, read from `sheaf.json`. */
export type Config = {
  siteUrl: URL;
  /** The path every generated URL is served under; always starts and ends with `/`. */
  basePath: string;
  /** IANA timezone name that decides when a date-only post counts as published. */
  timezone: string;
  /** The Shiki themes code is highlighted with. */
  highlight: { light: string; dark: string };
};

// `images` is reserved for a later feature and ignored for now.
const knownKeys = ["siteUrl", "timezone", "highlight", "images"];

const defaultTimezone = "UTC";

const defaultThemes = { light: "github-light", dark: "github-dark" };

/** A problem with one key, before it is located in `sheaf.json`. */
type Problem = { message: string; hint?: string };

/** Parses the text of `sheaf.json`, reporting every problem found in it at once. */
export function parseConfig(
  json: string,
  sourcePath: string,
): Result<Config, Diagnostic[]> {
  const badConfig = (message: string, hint?: string): Diagnostic => ({
    severity: "error",
    title: "BAD CONFIG",
    message,
    sourcePath,
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

  const siteUrl = parseSiteUrl(fields.siteUrl);
  if (!siteUrl.ok)
    problems.push(badConfig(siteUrl.error.message, siteUrl.error.hint));

  const timezone = parseTimezone(fields.timezone);
  if (!timezone.ok) problems.push(badConfig(timezone.error));

  const highlight = parseHighlight(fields.highlight);
  if (!highlight.ok) {
    problems.push(
      ...highlight.error.map(({ message, hint }) => badConfig(message, hint)),
    );
  }

  if (!siteUrl.ok || !timezone.ok || !highlight.ok || problems.length > 0) {
    return err(problems);
  }

  return ok({
    siteUrl: siteUrl.value,
    basePath: basePathOf(siteUrl.value),
    timezone: timezone.value,
    highlight: highlight.value,
  });
}

/** `{ "theme": { "light": …, "dark": … } }`, where every part is optional. */
function parseHighlight(
  value: unknown,
): Result<Config["highlight"], Problem[]> {
  if (value === undefined) return ok(defaultThemes);
  if (!isObject(value)) {
    return err([{ message: '"highlight" must be an object.' }]);
  }
  const problems = unknownKeys(value, ["theme"], "highlight.");
  const theme = value.theme ?? {};
  if (!isObject(theme)) {
    return err([
      ...problems,
      { message: '"highlight.theme" must be an object.' },
    ]);
  }
  problems.push(...unknownKeys(theme, ["light", "dark"], "highlight.theme."));
  const light = parseTheme(theme.light, "light");
  const dark = parseTheme(theme.dark, "dark");
  if (!light.ok) problems.push(light.error);
  if (!dark.ok) problems.push(dark.error);
  if (!light.ok || !dark.ok || problems.length > 0) return err(problems);
  return ok({ light: light.value, dark: dark.value });
}

function parseTheme(
  value: unknown,
  variant: keyof Config["highlight"],
): Result<string, Problem> {
  if (value === undefined) return ok(defaultThemes[variant]);
  if (typeof value !== "string") {
    return err({ message: `"highlight.theme.${variant}" must be a string.` });
  }
  if (Object.hasOwn(bundledThemes, value)) return ok(value);
  const [closest] = suggestions(value, Object.keys(bundledThemes), 1);
  return err({
    message: `The ${variant} theme "${value}" is not one of Shiki's themes.`,
    hint:
      closest === undefined
        ? "The themes are listed at https://shiki.style/themes."
        : `Did you mean "${closest}"?`,
  });
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

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function parseSiteUrl(
  value: unknown,
): Result<URL, { message: string; hint?: string }> {
  if (value === undefined) {
    return err({
      message: 'The required key "siteUrl" is missing.',
      hint: "Use a full URL such as https://example.com/",
    });
  }
  const fullUrlHint = "Use a full URL such as https://example.com/";
  if (typeof value !== "string") {
    return err({ message: '"siteUrl" must be a string.', hint: fullUrlHint });
  }
  const notAFullUrl = err({
    message: `"${value}" is not a full URL.`,
    hint: fullUrlHint,
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
        message: `"${value}" has a query or a fragment.`,
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
