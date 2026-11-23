import { describe, expect, test } from "bun:test";
import { join } from "node:path";
import { fixturePath } from "./support/fixtures";

const ENTRY = join(import.meta.dir, "../src/index.ts");
const SLOW = 60_000;

async function sheaf(args: string[], cwd: string) {
  const child = Bun.spawn([process.execPath, ENTRY, ...args], {
    cwd,
    stdout: "pipe",
    stderr: "pipe",
    env: { ...process.env, NO_COLOR: "1" },
  });
  const [stdout, stderr, exitCode] = await Promise.all([
    new Response(child.stdout).text(),
    new Response(child.stderr).text(),
    child.exited,
  ]);
  return { stdout, stderr, exitCode };
}

describe("sheaf", () => {
  test(
    "build succeeds on a valid site and says how many pages",
    async () => {
      const { stdout, exitCode } = await sheaf(
        ["build"],
        fixturePath("minimal"),
      );

      expect(exitCode).toBe(0);
      expect(stdout).toMatch(/Built 1 page in \d+\.\d+s/);
    },
    SLOW,
  );

  test(
    "check fails with the diagnostics and a count",
    async () => {
      const { stdout, exitCode } = await sheaf(
        ["check"],
        fixturePath("broken-links"),
      );

      expect(exitCode).toBe(1);
      expect(stdout).toContain("-- BROKEN LINK ---");
      expect(stdout).toContain("content/posts/2026-11-23-hello-world.md:5:6");
      expect(stdout).toContain("^^^^");
      expect(stdout).toContain("Found 2 errors");
    },
    SLOW,
  );

  test("prints help and exits 2 for an unknown command", async () => {
    const { stderr, exitCode } = await sheaf(["frobnicate"], import.meta.dir);

    expect(exitCode).toBe(2);
    expect(stderr).toContain("Usage:");
  });

  test("prints help for --help", async () => {
    const { stdout, exitCode } = await sheaf(["--help"], import.meta.dir);

    expect(exitCode).toBe(0);
    expect(stdout).toContain("sheaf build");
  });

  test("prints the package version", async () => {
    const { stdout, exitCode } = await sheaf(["--version"], import.meta.dir);

    expect(exitCode).toBe(0);
    expect(stdout.trim()).toBe("0.1.0");
  });
});
