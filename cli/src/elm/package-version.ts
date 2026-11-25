import type { Diagnostic } from "../diagnostics/diagnostic";
import { err, ok, type Result } from "../result";

const SUPPORTED_MAJOR = 1;

/**
 * The Elm package every site needs, and the versions this CLI works with: any
 * version of the supported major. The range text is built from that major, so
 * the two cannot differ.
 */
export const SUPPORTED_ELM_PACKAGE = {
  name: "ianramosc/elm-sheaf",
  range: `${SUPPORTED_MAJOR}.0.0 <= v < ${SUPPORTED_MAJOR + 1}.0.0`,
};

/**
 * Checks that a site gets the Sheaf Elm package exactly once, at a version
 * this CLI supports: either as a dependency or, for a clone of the repository,
 * as a source directory holding `Sheaf.elm`. `hasLocalSheaf` receives a
 * source directory as written in `elm.json`.
 */
export function checkElmPackage(
  elmJson: string,
  hasLocalSheaf: (sourceDirectory: string) => boolean,
): Result<void, Diagnostic[]> {
  const parsed = parseElmJson(elmJson);
  if (!parsed.ok) return parsed;
  const { version, sourceDirectories } = parsed.value;
  const isLocal = sourceDirectories.some(hasLocalSheaf);

  if (version === undefined) {
    return isLocal ? ok(undefined) : err([missing()]);
  }
  if (isLocal) return err([twice()]);
  return isSupported(version) ? ok(undefined) : err([unsupported(version)]);
}

type ElmJson = { version: string | undefined; sourceDirectories: string[] };

function parseElmJson(text: string): Result<ElmJson, Diagnostic[]> {
  let json: unknown;
  try {
    json = JSON.parse(text);
  } catch (error) {
    const reason = error instanceof Error ? error.message : String(error);
    return err([badElmJson(`This file is not valid JSON: ${reason}`)]);
  }
  if (!isRecord(json)) {
    return err([
      badElmJson("The top level of this file must be a JSON object."),
    ]);
  }
  const dependencies = isRecord(json.dependencies) ? json.dependencies : {};
  const direct = isRecord(dependencies.direct) ? dependencies.direct : {};
  const version = direct[SUPPORTED_ELM_PACKAGE.name];
  if (version !== undefined && typeof version !== "string") {
    return err([
      badElmJson(
        `The version of ${SUPPORTED_ELM_PACKAGE.name} must be a string.`,
      ),
    ]);
  }
  const directories = json["source-directories"];
  return ok({
    version,
    sourceDirectories: Array.isArray(directories)
      ? directories.filter((entry) => typeof entry === "string")
      : [],
  });
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** Compares `MAJOR.MINOR.PATCH` numerically, so `1.10.0` is not below `1.9.0`. */
function isSupported(version: string): boolean {
  const match = /^(\d+)\.(\d+)\.(\d+)$/.exec(version);
  return match !== null && Number(match[1]) === SUPPORTED_MAJOR;
}

function badElmJson(message: string): Diagnostic {
  return { severity: "error", title: "BAD ELM JSON", message };
}

function unsupported(version: string): Diagnostic {
  return {
    severity: "error",
    title: "UNSUPPORTED SHEAF VERSION",
    message: `elm.json depends on ${SUPPORTED_ELM_PACKAGE.name} ${version}, but this CLI supports ${SUPPORTED_ELM_PACKAGE.range}.`,
    hint: `Run \`elm install ${SUPPORTED_ELM_PACKAGE.name}\` after editing elm.json, or install a CLI that supports ${version}.`,
  };
}

function missing(): Diagnostic {
  return {
    severity: "error",
    title: "SHEAF PACKAGE MISSING",
    message: `elm.json has no ${SUPPORTED_ELM_PACKAGE.name} dependency, and none of its source-directories holds Sheaf.elm.`,
    hint: `Run \`elm install ${SUPPORTED_ELM_PACKAGE.name}\`.`,
  };
}

function twice(): Diagnostic {
  return {
    severity: "error",
    title: "SHEAF PACKAGE TWICE",
    message: `elm.json depends on ${SUPPORTED_ELM_PACKAGE.name} and also lists a source directory that holds Sheaf.elm, so Elm would find every Sheaf module twice.`,
    hint: `Remove the Sheaf repository's \`src\` from \`source-directories\`, or remove the \`${SUPPORTED_ELM_PACKAGE.name}\` dependency.`,
  };
}
