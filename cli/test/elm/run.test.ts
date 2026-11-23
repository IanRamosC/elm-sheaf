import { afterEach, describe, expect, test } from "bun:test";
import {
  chmodSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { parseConfig } from "../../src/config/config";
import { loadContent, readContentFiles } from "../../src/content/load";
import { renderDiagnostic } from "../../src/diagnostics/render";
import { compileElm, findElm } from "../../src/elm/compile";
import { generateElm } from "../../src/elm/generate";
import { assignValueNames } from "../../src/elm/names";
import {
  encodeRequest,
  type ParsedDocument,
  PROTOCOL_VERSION,
  type Request,
} from "../../src/elm/protocol";
import { runElm } from "../../src/elm/run";
import { writeGenerated } from "../../src/emit/write";
import { checkLinks } from "../../src/markdown/links";
import { parseMarkdown } from "../../src/markdown/parse";

const FIXTURES = join(import.meta.dir, "../fixtures");

// The first compile of a site can take several seconds, and elm make runs
// again for each fixture.
const COMPILE_TIMEOUT_MS = 60_000;

const scratchDirectories: string[] = [];

function scratchDirectory(): string {
  const directory = mkdtempSync(join(tmpdir(), "sheaf-run-"));
  scratchDirectories.push(directory);
  return directory;
}

afterEach(() => {
  for (const directory of scratchDirectories.splice(0)) {
    rmSync(directory, { recursive: true, force: true });
  }
});

const emptyRequest: Request = {
  protocolVersion: PROTOCOL_VERSION,
  build: { siteUrl: "https://example.com/", basePath: "/", mode: "production" },
  collections: [],
  documents: [],
};

function respondingWorker(body: string): string {
  return `(function (scope) {
    ${body}
    scope.Elm = {
      SheafMain: {
        init: function () {
          var subscriber;
          return {
            ports: {
              sheafResponse: { subscribe: function (callback) { subscriber = callback; } },
              sheafRequest: { send: function () { subscriber({ pages: [], diagnostics: [] }); } },
            },
          };
        },
      },
    };
  })(this);`;
}

function compiledFile(source: string): string {
  const path = join(scratchDirectory(), "site.js");
  writeFileSync(path, source);
  return path;
}

describe("runElm", () => {
  test("collects console output and still responds", async () => {
    const path = compiledFile(`(function (scope) {
      scope.Elm = {
        SheafMain: {
          init: function () {
            console.warn("Compiled in DEV mode.");
            console.log("starting");
            var subscriber;
            return {
              ports: {
                sheafResponse: { subscribe: function (callback) { subscriber = callback; } },
                sheafRequest: { send: function () { subscriber({ pages: [], diagnostics: [] }); } },
              },
            };
          },
        },
      };
    })(this);`);

    const result = await runElm(path, emptyRequest);

    expect(result).toEqual({
      ok: true,
      value: {
        response: { pages: [], diagnostics: [] },
        output: ["warn: Compiled in DEV mode.", "starting"],
      },
    });
  });

  test("gives the worker the timers Elm's scheduler uses", async () => {
    const path = compiledFile(
      respondingWorker("setTimeout(function () {}, 0); clearTimeout(0);"),
    );

    const result = await runElm(path, emptyRequest);

    expect(result.ok).toBe(true);
  });

  test("reports an exception thrown while sending as a runtime error", async () => {
    const path = compiledFile(`(function (scope) {
      scope.Elm = {
        SheafMain: {
          init: function () {
            return {
              ports: {
                sheafResponse: { subscribe: function () {} },
                sheafRequest: { send: function () { throw new Error("Debug.todo hit"); } },
              },
            };
          },
        },
      };
    })(this);`);

    const result = await runElm(path, emptyRequest);

    expect(result).toEqual({
      ok: false,
      error: [
        {
          severity: "error",
          title: "ELM RUNTIME ERROR",
          message: "Debug.todo hit",
          hint: "This is a crash in the site's Elm code or in Sheaf. Run with --drafts to check it isn't specific to one document.",
        },
      ],
    });
  });

  test("reports an exception thrown later, from a timer callback", async () => {
    const path = compiledFile(`(function (scope) {
      scope.Elm = {
        SheafMain: {
          init: function () {
            var subscriber;
            return {
              ports: {
                sheafResponse: { subscribe: function (callback) { subscriber = callback; } },
                sheafRequest: {
                  send: function () {
                    setTimeout(function () { throw new Error("late"); }, 0);
                    setTimeout(function () { subscriber({ pages: [], diagnostics: [] }); }, 20);
                  },
                },
              },
            };
          },
        },
      };
    })(this);`);

    const result = await runElm(path, emptyRequest);

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error[0]?.title).toBe("ELM RUNTIME ERROR");
    expect(result.error[0]?.message).toBe("late");
  });

  test("does not keep the process alive for timers left pending", async () => {
    const path = compiledFile(`(function (scope) {
      scope.Elm = {
        SheafMain: {
          init: function () {
            var subscriber;
            return {
              ports: {
                sheafResponse: { subscribe: function (callback) { subscriber = callback; } },
                sheafRequest: {
                  send: function () {
                    setTimeout(function () {}, 30000);
                    subscriber({ pages: [], diagnostics: [] });
                  },
                },
              },
            };
          },
        },
      };
    })(this);`);
    const script = `import { runElm } from ${JSON.stringify(join(import.meta.dir, "../../src/elm/run"))};
      await runElm(${JSON.stringify(path)}, ${JSON.stringify(emptyRequest)});`;
    const started = Date.now();

    const child = Bun.spawn([process.execPath, "-e", script]);
    const exitCode = await child.exited;

    expect(exitCode).toBe(0);
    // A leftover timer would hold the process open until it fired, 30 s later.
    expect(Date.now() - started).toBeLessThan(10_000);
  }, 40_000);

  test("treats a response that is not in the protocol as a bug", async () => {
    const path = compiledFile(`(function (scope) {
      scope.Elm = {
        SheafMain: {
          init: function () {
            var subscriber;
            return {
              ports: {
                sheafResponse: { subscribe: function (callback) { subscriber = callback; } },
                sheafRequest: { send: function () { subscriber({ pages: "nope" }); } },
              },
            };
          },
        },
      };
    })(this);`);

    await expect(runElm(path, emptyRequest)).rejects.toThrow(
      "pages must be a list",
    );
  });
});

function installFakeElm(directory: string, version: string): string {
  mkdirSync(directory, { recursive: true });
  const path = join(directory, "elm");
  writeFileSync(path, `#!/bin/sh\necho ${version}\n`);
  chmodSync(path, 0o755);
  return path;
}

describe("findElm", () => {
  test("prefers the site's own copy over PATH", async () => {
    const siteRoot = scratchDirectory();
    const projectElm = installFakeElm(
      join(siteRoot, "node_modules/.bin"),
      "0.19.3",
    );
    const pathDirectory = join(scratchDirectory(), "bin");
    installFakeElm(pathDirectory, "0.19.3");

    const found = await findElm(siteRoot, { path: pathDirectory });

    expect(found).toEqual({ ok: true, value: projectElm });
  });

  test("falls back to PATH", async () => {
    const pathDirectory = join(scratchDirectory(), "bin");
    const globalElm = installFakeElm(pathDirectory, "0.19.3");

    const found = await findElm(scratchDirectory(), { path: pathDirectory });

    expect(found).toEqual({ ok: true, value: globalElm });
  });

  test("reports a missing Elm with how to install it", async () => {
    const found = await findElm(scratchDirectory(), {
      path: scratchDirectory(),
    });

    expect(found).toEqual({
      ok: false,
      error: [
        {
          severity: "error",
          title: "ELM NOT FOUND",
          message:
            "Sheaf compiles templates with Elm, but there is no `elm` in node_modules/.bin or on your PATH.",
          hint: "Install Elm 0.19.3: npm install --save-dev elm@0.19.3",
        },
      ],
    });
  });

  test("reports an Elm of another version, naming it and its path", async () => {
    const pathDirectory = join(scratchDirectory(), "bin");
    const oldElm = installFakeElm(pathDirectory, "0.19.1");

    const found = await findElm(scratchDirectory(), { path: pathDirectory });

    expect(found).toEqual({
      ok: false,
      error: [
        {
          severity: "error",
          title: "WRONG ELM VERSION",
          message: `Sheaf needs Elm 0.19.3, but ${oldElm} is version 0.19.1.`,
          hint: "Install Elm 0.19.3: npm install --save-dev elm@0.19.3",
        },
      ],
    });
  });
});

/**
 * Loads the site, checks it and writes `.sheaf/gen/`, returning the request
 * the worker will be given. Unlike `build`, it leaves compiling to the test,
 * which compiles without `--optimize`.
 */
async function generateSite(siteRoot: string): Promise<Request> {
  const configText = readFileSync(join(siteRoot, "sheaf.json"), "utf8");
  const config = parseConfig(configText, "sheaf.json");
  if (!config.ok) throw new Error("fixture config must be valid");

  const files = await readContentFiles(siteRoot);
  const loaded = loadContent(
    files,
    config.value,
    new Date("2026-12-01T00:00:00Z"),
    "production",
  );
  if (!loaded.ok) throw new Error("fixture content must load");
  const documents = loaded.value;

  const parsed: ParsedDocument[] = documents.map((source) => {
    const tree = parseMarkdown(source);
    if (!tree.ok) throw new Error("fixture Markdown must parse");
    const checked = checkLinks(tree.value, source, documents);
    if (!checked.ok) throw new Error("fixture links must resolve");
    return { source, tree: checked.value };
  });

  const names = assignValueNames(documents);
  if (!names.ok) throw new Error("fixture slugs must have valid names");
  const collections = [...new Set(documents.map((d) => d.collection))];
  await writeGenerated(
    siteRoot,
    generateElm(collections, documents, names.value),
  );

  return encodeRequest(
    {
      siteUrl: config.value.siteUrl.href,
      basePath: config.value.basePath,
      mode: "production",
    },
    collections,
    parsed,
  );
}

async function realElm(siteRoot: string): Promise<string> {
  const found = await findElm(siteRoot);
  if (!found.ok) throw new Error("these tests need Elm 0.19.3 on PATH");
  return found.value;
}

describe("a Sheaf site", () => {
  test(
    "compiles without --optimize and renders its pages",
    async () => {
      const siteRoot = join(FIXTURES, "minimal");
      const request = await generateSite(siteRoot);
      const elm = await realElm(siteRoot);

      const compiled = await compileElm(siteRoot, { elm, optimize: false });
      expect(compiled.ok).toBe(true);
      if (!compiled.ok) return;
      const ran = await runElm(compiled.value, request);

      expect(ran.ok).toBe(true);
      if (!ran.ok) return;
      expect(ran.value.response.diagnostics).toEqual([]);
      const page = ran.value.response.pages.find(
        ({ path }) => path === "posts/hello-world/index.html",
      );
      expect(page?.html).toContain('href="/posts/hello-world/#top"');
      expect(ran.value.output.some((line) => line.startsWith("warn:"))).toBe(
        true,
      );
    },
    COMPILE_TIMEOUT_MS,
  );

  test(
    "turns a compiler error into a diagnostic with the compiler's title",
    async () => {
      const siteRoot = join(FIXTURES, "compile-error");
      await writeGenerated(siteRoot, generateElm([], [], new Map()));
      const elm = await realElm(siteRoot);

      const compiled = await compileElm(siteRoot, { elm, optimize: false });

      expect(compiled.ok).toBe(false);
      if (compiled.ok) return;
      expect(compiled.error).toHaveLength(1);
      const [diagnostic] = compiled.error;
      expect(diagnostic?.title).toBe("TYPE MISMATCH");
      expect(diagnostic?.severity).toBe("error");
      expect(diagnostic?.sourcePath).toBe("src/Site.elm");
      expect(diagnostic?.span).toEqual({
        start: { line: 9, column: 9 },
        end: { line: 11, column: 10 },
      });
      expect(diagnostic?.message).toContain(
        "The 1st argument to `site` is not what I expect:",
      );
      expect(diagnostic?.message).toContain(
        "But `site` needs the 1st argument",
      );
    },
    COMPILE_TIMEOUT_MS,
  );

  test(
    "renders a compiler error with the compiler's excerpt only",
    async () => {
      const siteRoot = join(FIXTURES, "compile-error");
      await writeGenerated(siteRoot, generateElm([], [], new Map()));
      const elm = await realElm(siteRoot);

      const compiled = await compileElm(siteRoot, { elm, optimize: false });

      expect(compiled.ok).toBe(false);
      if (compiled.ok) return;
      const [diagnostic] = compiled.error;
      if (diagnostic === undefined) throw new Error("expected a diagnostic");
      const source = readFileSync(join(siteRoot, "src/Site.elm"), "utf8");
      const rendered = renderDiagnostic(diagnostic, source);
      expect(rendered.split("\n")[0]).toEndWith(" src/Site.elm:9:9");
      expect(rendered.split("language = 1")).toHaveLength(2);
    },
    COMPILE_TIMEOUT_MS,
  );
});
