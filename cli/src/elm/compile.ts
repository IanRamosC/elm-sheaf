import { execFile } from "node:child_process";
import { access, constants } from "node:fs/promises";
import { delimiter, join, relative } from "node:path";
import type { Diagnostic, Span } from "../diagnostics/diagnostic";
import { err, ok, type Result } from "../result";

const REQUIRED_ELM_VERSION = "0.19.3";
const INSTALL_HINT = `Install Elm ${REQUIRED_ELM_VERSION}: npm install --save-dev elm@${REQUIRED_ELM_VERSION}`;
const ENTRY_POINT = ".sheaf/gen/SheafMain.elm";
const COMPILED_OUTPUT = ".sheaf/site.js";

type Execution = { exitCode: number; stdout: string; stderr: string };

/** Runs a program without a shell; a non-zero exit is a result, not an exception. */
function run(
  program: string,
  args: string[],
  workingDirectory: string,
): Promise<Execution> {
  return new Promise((resolve, reject) => {
    execFile(
      program,
      args,
      { cwd: workingDirectory, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 },
      (error, stdout, stderr) => {
        if (error === null) {
          resolve({ exitCode: 0, stdout, stderr });
        } else if (typeof error.code === "number") {
          resolve({ exitCode: error.code, stdout, stderr });
        } else {
          reject(error);
        }
      },
    );
  });
}

async function isExecutable(path: string): Promise<boolean> {
  try {
    await access(path, constants.X_OK);
    return true;
  } catch {
    return false;
  }
}

async function firstExecutable(
  candidates: string[],
): Promise<string | undefined> {
  for (const candidate of candidates) {
    if (await isExecutable(candidate)) return candidate;
  }
  return undefined;
}

/**
 * Finds Elm 0.19.3, looking for the site's own copy in `node_modules/.bin`
 * before `PATH` (`options.path` stands in for it, so tests need not change
 * the environment).
 */
export async function findElm(
  siteRoot: string,
  options: { path?: string } = {},
): Promise<Result<string, Diagnostic[]>> {
  const searchPath = options.path ?? process.env.PATH ?? "";
  const found = await firstExecutable([
    join(siteRoot, "node_modules/.bin/elm"),
    ...searchPath
      .split(delimiter)
      .filter((directory) => directory !== "")
      .map((directory) => join(directory, "elm")),
  ]);
  if (found === undefined) {
    return err([
      {
        severity: "error",
        title: "ELM NOT FOUND",
        message:
          "Sheaf compiles templates with Elm, but there is no `elm` in node_modules/.bin or on your PATH.",
        hint: INSTALL_HINT,
      },
    ]);
  }

  const { stdout } = await run(found, ["--version"], siteRoot);
  const version = stdout.trim();
  if (version !== REQUIRED_ELM_VERSION) {
    return err([
      {
        severity: "error",
        title: "WRONG ELM VERSION",
        message: `Sheaf needs Elm ${REQUIRED_ELM_VERSION}, but ${found} is version ${version}.`,
        hint: INSTALL_HINT,
      },
    ]);
  }
  return ok(found);
}

/** Elm writes messages as plain strings mixed with styled `{ string, … }` objects. */
function messageText(message: unknown): string {
  if (!Array.isArray(message)) return "";
  return message
    .map((part: unknown) =>
      typeof part === "string"
        ? part
        : ((part as { string?: string }).string ?? ""),
    )
    .join("");
}

type ElmPosition = { line: number; column: number };
type ElmProblem = {
  title: string;
  message: unknown;
  region: { start: ElmPosition; end: ElmPosition };
};
type ElmReport =
  | {
      type: "compile-errors";
      errors: { path: string; problems: ElmProblem[] }[];
    }
  | { type: "error"; path: string | null; title: string; message: unknown };

/**
 * Elm's region end is already exclusive (a one-character `}` at column 9 ends
 * at column 10), which is the convention of our `Span`, so it is used as is.
 */
function spanOf({ start, end }: ElmProblem["region"]): Span {
  return { start, end };
}

function diagnosticsOf(report: ElmReport, siteRoot: string): Diagnostic[] {
  const relativePath = (path: string) =>
    relative(siteRoot, path).split("\\").join("/");
  if (report.type === "error") {
    return [
      {
        severity: "error",
        title: report.title,
        message: messageText(report.message),
        ...(report.path !== null && { sourcePath: relativePath(report.path) }),
      },
    ];
  }
  return report.errors.flatMap(({ path, problems }) =>
    problems.map((problem) => ({
      severity: "error" as const,
      title: problem.title,
      message: messageText(problem.message),
      sourcePath: relativePath(path),
      span: spanOf(problem.region),
      excerpt: false as const,
    })),
  );
}

/**
 * Compiles the generated entry point with `elm`, returning the path of the
 * JavaScript it wrote. `--optimize` is for `build`; `dev` leaves it off.
 */
export async function compileElm(
  siteRoot: string,
  options: { elm: string; optimize: boolean },
): Promise<Result<string, Diagnostic[]>> {
  const args = [
    "make",
    ENTRY_POINT,
    "--output",
    COMPILED_OUTPUT,
    "--report=json",
    ...(options.optimize ? ["--optimize"] : []),
  ];
  const { exitCode, stderr } = await run(options.elm, args, siteRoot);
  if (exitCode === 0) return ok(join(siteRoot, COMPILED_OUTPUT));

  let report: ElmReport;
  try {
    report = JSON.parse(stderr);
  } catch {
    return err([
      {
        severity: "error",
        title: "ELM COMPILER FAILED",
        message: stderr.trim() || `elm make exited with code ${exitCode}.`,
      },
    ]);
  }
  return err(diagnosticsOf(report, siteRoot));
}
