import { execFile } from "node:child_process";
import { access, constants, rm } from "node:fs/promises";
import { delimiter, join, relative } from "node:path";
import type { Diagnostic, Span } from "../diagnostics/diagnostic";
import { err, ok, type Result } from "../result";

const REQUIRED_ELM_VERSION = "0.19.3";
/** npm's `elm` package has no `0.19.3`; its release of Elm 0.19.3 is `0.19.3-0`. */
const ELM_NPM_VERSION = "0.19.3-0";
const INSTALL_HINT = `Install Elm ${REQUIRED_ELM_VERSION}: npm install --save-dev elm@${ELM_NPM_VERSION}`;
const ENTRY_POINT = ".sheaf/gen/SheafMain.elm";
const COMPILED_OUTPUT = ".sheaf/site.js";

type Execution = { exitCode: number; stdout: string; stderr: string };

/**
 * Runs a program without a shell, except the `cmd.exe` a batch file needs;
 * a non-zero exit is a result, not an exception.
 */
function run(
  program: string,
  args: string[],
  workingDirectory: string,
): Promise<Execution> {
  const [file, fileArgs, verbatim] = isBatchFile(program)
    ? batchCommand(program, args)
    : [program, args, false];
  return new Promise((resolve, reject) => {
    execFile(
      file,
      fileArgs,
      {
        cwd: workingDirectory,
        encoding: "utf8",
        maxBuffer: 64 * 1024 * 1024,
        windowsVerbatimArguments: verbatim,
      },
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

function isBatchFile(program: string): boolean {
  return /\.(cmd|bat)$/i.test(program);
}

/**
 * Windows starts a batch file, such as npm's `elm.cmd`, only through
 * `cmd.exe`, and `execFile` quotes arguments by rules `cmd.exe` doesn't
 * follow. So the command line is built here and passed as it is: every part
 * in double quotes, which keeps spaces and `&`, `|`, `<`, `>` and `^`
 * literal, all inside one more pair that `/s` strips. `/d` skips AutoRun
 * commands. A `%` would still expand, but Sheaf's arguments have none.
 */
function batchCommand(
  program: string,
  args: string[],
): [string, string[], boolean] {
  const line = [program, ...args].map((part) => `"${part}"`).join(" ");
  return [
    process.env.ComSpec ?? "cmd.exe",
    ["/d", "/s", "/c", `"${line}"`],
    true,
  ];
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
 * The names `elm` goes by. On Windows a program needs an extension, and npm
 * puts a shell script for Unix, with none, next to `elm.cmd`.
 */
const ELM_NAMES =
  process.platform === "win32" ? ["elm.exe", "elm.cmd"] : ["elm"];

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
  const directories = [
    join(siteRoot, "node_modules/.bin"),
    ...searchPath.split(delimiter).filter((directory) => directory !== ""),
  ];
  const found = await firstExecutable(
    directories.flatMap((directory) =>
      ELM_NAMES.map((name) => join(directory, name)),
    ),
  );
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
  // `elm make` leaves the old output in place when it fails; remove it first
  // so nothing can run a site that no longer matches its source.
  await rm(join(siteRoot, COMPILED_OUTPUT), { force: true });
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
