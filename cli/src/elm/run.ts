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

type Outcome = Result<{ response: Response; output: string[] }, Diagnostic[]>;

/**
 * Runs the compiled worker once: sends it the request and waits for its
 * response. The code runs in a fresh context, which keeps it from reaching
 * the host's globals by accident (it is not a security sandbox). That context
 * has none of its own, so it is given the few the Elm runtime uses. Console
 * output is returned rather than printed, because only `cli/` writes to the
 * terminal.
 *
 * The worker's timers are wrapped so that a callback that throws becomes a
 * runtime error instead of crashing the host, and so that any still pending
 * when the run ends are cancelled instead of keeping the process alive.
 */
export async function runElm(
  compiledJs: string,
  request: Request,
): Promise<Result<{ response: Response; output: string[] }, Diagnostic[]>> {
  const code = await readFile(compiledJs, "utf8");
  const output: string[] = [];

  return new Promise((resolve, reject) => {
    const workerTimers = new Set<ReturnType<typeof setTimeout>>();
    const responseTimeout = setTimeout(
      () =>
        finish(() =>
          reject(
            new Error(
              `The Elm worker did not respond within ${RESPONSE_TIMEOUT_MS / 1000} seconds`,
            ),
          ),
        ),
      RESPONSE_TIMEOUT_MS,
    );
    const finish = (conclude: () => void) => {
      clearTimeout(responseTimeout);
      for (const timer of workerTimers) clearTimeout(timer);
      conclude();
    };
    const settle = (outcome: Outcome) => finish(() => resolve(outcome));

    const context = createContext({
      console: captureConsole(output),
      setTimeout: (callback: () => void, delay?: number) => {
        const timer = setTimeout(() => {
          workerTimers.delete(timer);
          try {
            callback();
          } catch (thrown) {
            settle(err([runtimeError(thrown)]));
          }
        }, delay);
        workerTimers.add(timer);
        return timer;
      },
      clearTimeout: (timer: ReturnType<typeof setTimeout>) => {
        workerTimers.delete(timer);
        clearTimeout(timer);
      },
    });

    try {
      runInContext(code, context, { filename: compiledJs });
      const worker: ElmWorker = context.Elm.SheafMain.init();
      worker.ports.sheafResponse.subscribe((value) => {
        const response = decodeResponse(value);
        if (response.ok) {
          settle(ok({ response: response.value, output }));
        } else {
          // Our own Elm code produced it, so a bad shape is a bug in Sheaf.
          finish(() =>
            reject(
              new Error(
                `The Elm worker sent a bad response: ${response.error}`,
              ),
            ),
          );
        }
      });
      worker.ports.sheafRequest.send(request);
    } catch (thrown) {
      settle(err([runtimeError(thrown)]));
    }
  });
}
