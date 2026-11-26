import { describe, expect, test } from "bun:test";
import { join, resolve } from "node:path";
import { nextSteps, runtimeOf } from "../../src/cli/next-steps";

const cwd = resolve("/home/me");
const INSTALL_ELM =
  "Install Elm 0.19.3 (npm install -g elm@0.19.3-0, or from https://github.com/elm/compiler/releases) if it isn't on your PATH.";

describe("nextSteps", () => {
  test("under Bun installs the site's dependencies and runs its sheaf", () => {
    expect(nextSteps("my site", cwd, "bun")).toEqual([
      "cd 'my site'",
      "bun install",
      "bunx sheaf dev",
    ]);
  });

  test("from a standalone binary asks for Elm and runs sheaf itself", () => {
    expect(nextSteps("my site", cwd, "binary")).toEqual([
      INSTALL_ELM,
      "cd 'my site'",
      "sheaf dev",
    ]);
  });

  test("has no cd when the site is the current folder", () => {
    expect(nextSteps(".", cwd, "bun")).toEqual([
      "bun install",
      "bunx sheaf dev",
    ]);
    expect(nextSteps(cwd, cwd, "binary")).toEqual([INSTALL_ELM, "sheaf dev"]);
  });

  test("leaves a folder unquoted when the shell reads it as it is", () => {
    expect(nextSteps("my-blog", cwd, "binary")[1]).toBe("cd my-blog");
    expect(nextSteps("sites/blog_2.0", cwd, "bun")[0]).toBe(
      "cd sites/blog_2.0",
    );
  });

  test("quotes $ and backticks so the shell doesn't expand them", () => {
    expect(nextSteps("$HOME `date`", cwd, "bun")[0]).toBe("cd '$HOME `date`'");
  });

  test("quotes a single quote in the folder name", () => {
    expect(nextSteps("Ian's blog", cwd, "bun")[0]).toBe("cd 'Ian'\\''s blog'");
  });

  test("keeps the folder as it was typed, relative or absolute", () => {
    const absolute = join(cwd, "blog");
    expect(nextSteps(absolute, cwd, "bun")[0]).toContain(absolute);
  });
});

describe("runtimeOf", () => {
  test("is a binary when the entry is in a compiled binary's file system", () => {
    expect(runtimeOf("/$bunfs/root/sheaf-linux-x64")).toBe("binary");
    expect(runtimeOf("B:\\~BUN\\root\\sheaf-windows-x64.exe")).toBe("binary");
    expect(runtimeOf("B:/~BUN/root/sheaf-windows-x64.exe")).toBe("binary");
  });

  test("is Bun when the entry is a file on disk", () => {
    expect(runtimeOf("/home/me/site/node_modules/elm-sheaf/src/index.ts")).toBe(
      "bun",
    );
    expect(runtimeOf("C:\\Users\\me\\elm-sheaf\\cli\\src\\index.ts")).toBe(
      "bun",
    );
  });
});
