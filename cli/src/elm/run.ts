import { readFile } from "node:fs/promises";
import { format } from "node:util";
import { createContext, runInContext } from "node:vm";
import type { Diagnostic } from "../diagnostics/diagnostic";
import { err, ok, type Result } from "../result";
import { decodeResponse, type Request, type Response } from "./protocol";

const RESPONSE_TIMEOUT_MS = 60_000;
const CONSOLE_LEVELS = ["log", "info", "warn", "error", "debug"] as const;

type ElmWorker = {
  ports: {
    sheafRequest: { send(request: Request): void };
    sheafResponse: { subscribe(listener: (response: unknown) => void): void };
  };
};

/** One line per console call; `log` is the default level, so it carries no prefix. */
function captureConsole(output: string[]) {
  return Object.fromEntries(
    CONSOLE_LEVELS.map((level) => [
      level,
      (...args: unknown[]) => {
        const line = format(...args);
        output.push(level === "log" ? line : `${level}: ${line}`);
      },
    ]),
  );
}

/** The worker's `Error` class belongs to its own context, so `instanceof Error` cannot recognise it. */
function messageOf(thrown: unknown): string {
  if (typeof thrown === "object" && thrown !== null && "message" in thrown) {
    return String(thrown.message);
  }
  return String(thrown);
}

function runtimeError(thrown: unknown): Diagnostic {
  return {
    severity: "error",
    title: "ELM RUNTIME ERROR",
    message: messageOf(thrown),
    hint: "This is a crash in the site's Elm code or in Sheaf. Run with --drafts to check it isn't specific to one document.",
  };
}

/**
 * Runs the compiled worker once: sends it the request and waits for its
 * response. The code runs in a fresh context so it cannot touch the host;
 * that context has no globals, so it is given the few the Elm runtime uses.
 * Console output is returned rather than printed, because only `cli/` writes
 * to the terminal.
 */
export async function runElm(
  compiledJs: string,
  request: Request,
): Promise<Result<{ response: Response; output: string[] }, Diagnostic[]>> {
  const code = await readFile(compiledJs, "utf8");
  const output: string[] = [];
  const context = createContext({
    console: captureConsole(output),
    setTimeout,
    clearTimeout,
  });

  return new Promise((resolve, reject) => {
    const timeout = setTimeout(
      () =>
        reject(
          new Error(
            `The Elm worker did not respond within ${RESPONSE_TIMEOUT_MS / 1000} seconds`,
          ),
        ),
      RESPONSE_TIMEOUT_MS,
    );
    const settle = (
      result: Result<{ response: Response; output: string[] }, Diagnostic[]>,
    ) => {
      clearTimeout(timeout);
      resolve(result);
    };

    try {
      runInContext(code, context, { filename: compiledJs });
      const worker: ElmWorker = context.Elm.SheafMain.init();
      worker.ports.sheafResponse.subscribe((value) => {
        const response = decodeResponse(value);
        if (response.ok) {
          settle(ok({ response: response.value, output }));
        } else {
          // Our own Elm code produced it, so a bad shape is a bug in Sheaf.
          clearTimeout(timeout);
          reject(
            new Error(`The Elm worker sent a bad response: ${response.error}`),
          );
        }
      });
      worker.ports.sheafRequest.send(request);
    } catch (thrown) {
      settle(err([runtimeError(thrown)]));
    }
  });
}
