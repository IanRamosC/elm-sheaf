/**
 * Builds the standalone binary for this machine and uses it the way someone
 * who downloaded it would: from a folder outside the repository, with `elm`
 * from PATH and no `bun install` in the site.
 *
 *     bun run smoke-binary
 */
import { existsSync, mkdtempSync, readdirSync, rmSync } from "node:fs";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { delimiter, join, resolve } from "node:path";
import packageJson from "../package.json";
import { ELM_NPM_VERSION } from "../src/init/project-files";
import { pngBytes } from "../test/support/images";
import { buildBinary, hostTarget } from "./build-binaries";

const repository = resolve(import.meta.dir, "../..");
const SITE = "smoke site";

class SmokeFailure extends Error {}

type Run = { exitCode: number; stdout: string; stderr: string };

/**
 * The PATH without the `node_modules/.bin` folders that `bun run` adds, so
 * the binary finds the `elm` a user would have rather than one installed in
 * the repository or above it.
 */
function userEnv(): Record<string, string | undefined> {
  // Windows spells it Path, and child processes must not get it twice.
  const key =
    Object.keys(process.env).find((name) => name.toUpperCase() === "PATH") ??
    "PATH";
  const path = (process.env[key] ?? "")
    .split(delimiter)
    .filter((folder) => !/node_modules[\\/]\.bin[\\/]?$/.test(folder))
    .join(delimiter);
  return { ...process.env, [key]: path };
}

async function run(command: string[], cwd: string): Promise<Run> {
  const child = Bun.spawn(command, {
    cwd,
    env: userEnv(),
    stdout: "pipe",
    stderr: "pipe",
  });
  const [stdout, stderr, exitCode] = await Promise.all([
    new Response(child.stdout).text(),
    new Response(child.stderr).text(),
    child.exited,
  ]);
  return { exitCode, stdout, stderr };
}

/** Runs `command` and fails with everything it printed unless it exits 0. */
async function succeed(command: string[], cwd: string): Promise<Run> {
  const result = await run(command, cwd);
  if (result.exitCode !== 0) {
    throw new SmokeFailure(
      `\`${command.join(" ")}\` exited with ${result.exitCode}\n${printed(result)}`,
    );
  }
  return result;
}

function check(condition: boolean, what: string, result?: Run): void {
  if (condition) return;
  throw new SmokeFailure(
    result === undefined ? what : `${what}\n${printed(result)}`,
  );
}

function printed({ stdout, stderr }: Run): string {
  return `--- stdout\n${stdout}--- stderr\n${stderr}`;
}

const POST = `---
title: Smoke
date: 2026-01-01
summary: A post with code and a picture.
---

![A gradient](gradient.png)

\`\`\`rust
fn main() {
    println!("Hello");
}
\`\`\`
`;

async function smoke(work: string): Promise<void> {
  const binary = await buildBinary(hostTarget());

  const version = await succeed([binary, "--version"], work);
  check(
    version.stdout.trim() === packageJson.version,
    `--version printed ${JSON.stringify(version.stdout.trim())}, expected ${packageJson.version}`,
  );

  const init = await succeed(
    [binary, "init", SITE, "--local", repository],
    work,
  );
  const expected = [
    "Next steps:",
    `  Install Elm 0.19.3 (npm install -g elm@${ELM_NPM_VERSION}, or from https://github.com/elm/compiler/releases) if it isn't on your PATH.`,
    `  cd '${SITE}'`,
    "  sheaf dev",
  ];
  const closing = init.stdout.trimEnd().split("\n").slice(-expected.length);
  check(
    closing.join("\n") === expected.join("\n"),
    "init didn't print the next steps for a standalone binary",
    init,
  );

  const site = join(work, SITE);
  const post = join(site, "content/posts/smoke");
  await mkdir(post, { recursive: true });
  await writeFile(join(post, "index.md"), POST);
  await writeFile(join(post, "gradient.png"), pngBytes(1200, 800));

  const build = await succeed([binary, "build"], site);
  check(
    existsSync(join(site, "dist/index.html")),
    "build wrote no dist/index.html",
    build,
  );
  const html = await readFile(
    join(site, "dist/posts/smoke/index.html"),
    "utf8",
  );
  check(
    /<code class="language-rust"><span class="line"><span style="color:#/.test(
      html,
    ),
    "the post's Rust code block has no Shiki spans",
    build,
  );
  const images = readdirSync(join(site, "dist/_sheaf/images"));
  check(
    images.some((name) => name.endsWith(".webp")) &&
      html.includes('alt="A gradient"'),
    `the post's image wasn't encoded: dist/_sheaf/images has ${images.join(", ")}`,
    build,
  );
}

const work = mkdtempSync(join(tmpdir(), "sheaf-smoke-"));
try {
  await smoke(work);
  process.stdout.write(`The ${hostTarget()} binary works.\n`);
} catch (error) {
  if (!(error instanceof SmokeFailure)) throw error;
  process.stderr.write(`${error.message}\n`);
  process.exitCode = 1;
} finally {
  rmSync(work, { recursive: true, force: true });
}
