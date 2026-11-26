import { afterAll, describe, expect, test } from "bun:test";
import {
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import packageJson from "../package.json";

const CLI = join(import.meta.dir, "..");
const REPO = join(CLI, "..");
const scratch = mkdtempSync(join(tmpdir(), "sheaf-package-"));

afterAll(() => rmSync(scratch, { recursive: true, force: true }));

type Run = { exitCode: number; stdout: string; stderr: string };

/** Runs Bun with `args`, killing it after `timeoutMs` so that a stalled network cannot hang the test. */
function bun(args: string[], cwd: string, timeoutMs: number): Run {
  const child = Bun.spawnSync([process.execPath, ...args], {
    cwd,
    timeout: timeoutMs,
    stdout: "pipe",
    stderr: "pipe",
  });
  return {
    exitCode: child.exitCode ?? -1,
    stdout: child.stdout.toString(),
    stderr: child.stderr.toString(),
  };
}

/** What `bun pm pack` reports: one `packed <size> <path>` line per file. */
function packedFiles(output: string): string[] {
  return output
    .split("\n")
    .flatMap((line) => /^packed \S+ (.+)$/.exec(line.trim())?.[1] ?? []);
}

describe("the npm tarball", () => {
  const dryRun = bun(["pm", "pack", "--dry-run"], CLI, 30_000);
  const files = packedFiles(dryRun.stdout);

  test("is listed by `bun pm pack --dry-run`", () => {
    expect(dryRun.stderr).not.toContain("error");
    expect(dryRun.exitCode).toBe(0);
  });

  test("carries the manifest, the licence, the README and the sources", () => {
    expect(files).toEqual(
      expect.arrayContaining([
        "package.json",
        "README.md",
        "LICENSE",
        "src/index.ts",
        "src/init/starter.generated.ts",
      ]),
    );
  });

  test("leaves out tests, scripts, templates and build output", () => {
    const excluded = files.filter((path) =>
      /^(test|scripts|templates|out|\.sheaf)\//.test(path),
    );
    expect(excluded).toEqual([]);
  });

  test("declares both commands, pointing at the same file", () => {
    expect(packageJson.bin).toEqual({
      sheaf: "src/index.ts",
      "elm-sheaf": "src/index.ts",
    });
  });

  test("carries the same licence as the repository", () => {
    expect(readFileSync(join(CLI, "LICENSE"), "utf8")).toBe(
      readFileSync(join(REPO, "LICENSE"), "utf8"),
    );
  });
});

describe("the installed package", () => {
  test("runs as `sheaf` and as `elm-sheaf`", () => {
    const packed = bun(["pm", "pack", "--destination", scratch], CLI, 30_000);
    expect(packed.exitCode).toBe(0);
    const tarball = join(scratch, `elm-sheaf-${packageJson.version}.tgz`);

    const site = join(scratch, "site");
    mkdirSync(site);
    writeFileSync(join(site, "package.json"), "{}\n");

    // The dependencies come from the registry, so a network failure must
    // read as one rather than as a missing command.
    const added = bun(["add", tarball], site, 40_000);
    if (added.exitCode !== 0) {
      throw new Error(
        `bun add failed (exit ${added.exitCode}). Is the registry reachable?\n${added.stderr}`,
      );
    }

    for (const command of ["elm-sheaf", "sheaf"]) {
      const ran = bun(["x", command, "--version"], site, 8_000);
      expect({ command, ...ran }).toEqual({
        command,
        exitCode: 0,
        stdout: `${packageJson.version}\n`,
        stderr: "",
      });
    }
  }, 60_000);
});
