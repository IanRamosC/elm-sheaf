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
};

// `highlight` and `images` are reserved for later features and ignored for now.
const knownKeys = ["siteUrl", "timezone", "highlight", "images"];

const defaultTimezone = "UTC";

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
  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
    return err([
      badConfig("The top level of this file must be a JSON object."),
    ]);
  }
  const fields = parsed as Record<string, unknown>;

  const problems: Diagnostic[] = [];

  for (const key of Object.keys(fields)) {
    if (!knownKeys.includes(key)) {
      const [closest] = suggestions(key, knownKeys, 1);
      problems.push(
        badConfig(
          `I do not know the key "${key}".`,
          closest === undefined ? undefined : `Did you mean "${closest}"?`,
        ),
      );
    }
  }

  const siteUrl = parseSiteUrl(fields.siteUrl);
  if (!siteUrl.ok)
    problems.push(badConfig(siteUrl.error.message, siteUrl.error.hint));

  const timezone = parseTimezone(fields.timezone);
  if (!timezone.ok) problems.push(badConfig(timezone.error));

  if (!siteUrl.ok || !timezone.ok || problems.length > 0) return err(problems);

  return ok({
    siteUrl: siteUrl.value,
    basePath: basePathOf(siteUrl.value),
    timezone: timezone.value,
  });
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
    return url.protocol === "http:" || url.protocol === "https:"
      ? ok(url)
      : notAFullUrl;
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
