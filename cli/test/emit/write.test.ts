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
      { path: "index.html", content: "home" },
      { path: "posts/one/index.html", content: "one" },
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

    await writeSite(root, [{ path: "index.html", content: "home" }]);

    expect(readdirSync(join(root, "dist"))).toEqual(["index.html"]);
  });

  test("refuses a page path that would leave dist, before touching dist", async () => {
    const root = siteRoot();
    mkdirSync(join(root, "dist"));
    writeFileSync(join(root, "dist/previous.html"), "kept");

    await expect(
      writeSite(root, [{ path: "../escape.html", content: "" }]),
    ).rejects.toThrow("../escape.html");
    await expect(
      writeSite(root, [
        { path: "fine.html", content: "" },
        { path: "/etc/passwd", content: "" },
      ]),
    ).rejects.toThrow("/etc/passwd");
    expect(readFileSync(join(root, "dist/previous.html"), "utf8")).toBe("kept");
  });

  test("writes feeds and the sitemap next to the pages", async () => {
    const root = siteRoot();

    await writeSite(root, [
      { path: "index.html", content: "home" },
      { path: "feed.xml", content: "<rss/>" },
      { path: "atom.xml", content: "<feed/>" },
      { path: "sitemap.xml", content: "<urlset/>" },
    ]);

    expect(readdirSync(join(root, "dist")).sort()).toEqual([
      "atom.xml",
      "feed.xml",
      "index.html",
      "sitemap.xml",
    ]);
  });

  test("throws on clashing paths before touching dist", async () => {
    const root = siteRoot();
    mkdirSync(join(root, "dist"));
    writeFileSync(join(root, "dist/previous.html"), "kept");

    await expect(
      writeSite(root, [
        { path: "feed.xml", content: "" },
        { path: "feed.xml/index.html", content: "" },
      ]),
    ).rejects.toThrow("feed.xml");
    await expect(
      writeSite(root, [
        { path: "About/index.html", content: "" },
        { path: "about/index.html", content: "" },
      ]),
    ).rejects.toThrow(
      "Two outputs share the path About/index.html and about/index.html",
    );
    expect(readFileSync(join(root, "dist/previous.html"), "utf8")).toBe("kept");
  });
});
