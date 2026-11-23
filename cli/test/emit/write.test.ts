import { afterEach, describe, expect, test } from "bun:test";
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { writeGenerated, writeSite } from "../../src/emit/write";

const directories: string[] = [];

function siteRoot(): string {
  const root = mkdtempSync(join(tmpdir(), "sheaf-write-"));
  directories.push(root);
  return root;
}

afterEach(() => {
  for (const directory of directories.splice(0)) {
    rmSync(directory, { recursive: true, force: true });
  }
});

describe("writeGenerated", () => {
  test("leaves only the new files, dropping modules of collections that are gone", async () => {
    const root = siteRoot();
    mkdirSync(join(root, ".sheaf/gen/Content"), { recursive: true });
    writeFileSync(join(root, ".sheaf/gen/Content/Old.elm"), "module Old");

    await writeGenerated(
      root,
      new Map([
        ["SheafMain.elm", "main"],
        ["Content/Posts.elm", "posts"],
      ]),
    );

    expect(readdirSync(join(root, ".sheaf/gen/Content"))).toEqual([
      "Posts.elm",
    ]);
    expect(readFileSync(join(root, ".sheaf/gen/SheafMain.elm"), "utf8")).toBe(
      "main",
    );
  });
});

describe("writeSite", () => {
  test("clears dist, writes the pages and copies static files as they are", async () => {
    const root = siteRoot();
    mkdirSync(join(root, "dist"));
    writeFileSync(join(root, "dist/stale.html"), "old");
    mkdirSync(join(root, "static/fonts"), { recursive: true });
    writeFileSync(join(root, "static/robots.txt"), "User-agent: *");
    writeFileSync(join(root, "static/fonts/a.txt"), "font");

    await writeSite(root, [
      { path: "index.html", html: "home" },
      { path: "posts/one/index.html", html: "one" },
    ]);

    expect(existsSync(join(root, "dist/stale.html"))).toBe(false);
    expect(readFileSync(join(root, "dist/index.html"), "utf8")).toBe("home");
    expect(readFileSync(join(root, "dist/posts/one/index.html"), "utf8")).toBe(
      "one",
    );
    expect(readFileSync(join(root, "dist/robots.txt"), "utf8")).toBe(
      "User-agent: *",
    );
    expect(readFileSync(join(root, "dist/fonts/a.txt"), "utf8")).toBe("font");
  });

  test("works without a static folder", async () => {
    const root = siteRoot();

    await writeSite(root, [{ path: "index.html", html: "home" }]);

    expect(readdirSync(join(root, "dist"))).toEqual(["index.html"]);
  });

  test("refuses a page path that would leave dist", async () => {
    const root = siteRoot();

    await expect(
      writeSite(root, [{ path: "../escape.html", html: "" }]),
    ).rejects.toThrow("../escape.html");
    await expect(
      writeSite(root, [{ path: "/etc/passwd", html: "" }]),
    ).rejects.toThrow("/etc/passwd");
  });
});
