import { afterEach, describe, expect, test } from "bun:test";
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { listStaticFiles } from "../../src/emit/static";
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

    const staticFiles = await listStaticFiles(root);
    if (!staticFiles.ok) throw new Error("static/ should be listed");

    await writeSite(
      root,
      [
        { kind: "text", path: "index.html", content: "home" },
        { kind: "text", path: "posts/one/index.html", content: "one" },
      ],
      staticFiles.value,
    );

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

  test("writes text outputs and copies files", async () => {
    const root = siteRoot();
    const source = join(root, "photo.webp");
    writeFileSync(source, "image bytes");

    await writeSite(
      root,
      [
        { kind: "text", path: "index.html", content: "<p>Hi</p>" },
        { kind: "copy", path: "_sheaf/images/h-480.webp", source },
      ],
      [],
    );

    expect(readFileSync(join(root, "dist/index.html"), "utf8")).toBe(
      "<p>Hi</p>",
    );
    expect(
      readFileSync(join(root, "dist/_sheaf/images/h-480.webp"), "utf8"),
    ).toBe("image bytes");
  });

  test("refuses an output path that would leave dist, before touching dist", async () => {
    const root = siteRoot();
    mkdirSync(join(root, "dist"));
    writeFileSync(join(root, "dist/previous.html"), "kept");

    await expect(
      writeSite(
        root,
        [{ kind: "text", path: "../escape.html", content: "" }],
        [],
      ),
    ).rejects.toThrow("../escape.html");
    await expect(
      writeSite(
        root,
        [
          { kind: "text", path: "fine.html", content: "" },
          { kind: "text", path: "/etc/passwd", content: "" },
        ],
        [],
      ),
    ).rejects.toThrow("/etc/passwd");
    await expect(
      writeSite(
        root,
        [
          {
            kind: "copy",
            path: "../escape.png",
            source: join(root, "photo.png"),
          },
        ],
        [],
      ),
    ).rejects.toThrow("../escape.png");
    expect(readFileSync(join(root, "dist/previous.html"), "utf8")).toBe("kept");
  });

  test("writes feeds and the sitemap next to the pages", async () => {
    const root = siteRoot();

    await writeSite(
      root,
      [
        { kind: "text", path: "index.html", content: "home" },
        { kind: "text", path: "feed.xml", content: "<rss/>" },
        { kind: "text", path: "atom.xml", content: "<feed/>" },
        { kind: "text", path: "sitemap.xml", content: "<urlset/>" },
      ],
      [],
    );

    expect(readdirSync(join(root, "dist")).sort()).toEqual([
      "atom.xml",
      "feed.xml",
      "index.html",
      "sitemap.xml",
    ]);
  });

  test("throws on clashing paths, of either kind, before touching dist", async () => {
    const root = siteRoot();
    mkdirSync(join(root, "dist"));
    writeFileSync(join(root, "dist/previous.html"), "kept");

    await expect(
      writeSite(
        root,
        [
          { kind: "text", path: "feed.xml", content: "" },
          { kind: "text", path: "feed.xml/index.html", content: "" },
        ],
        [],
      ),
    ).rejects.toThrow("feed.xml");
    await expect(
      writeSite(
        root,
        [
          { kind: "text", path: "About/index.html", content: "" },
          { kind: "text", path: "about/index.html", content: "" },
        ],
        [],
      ),
    ).rejects.toThrow(
      "Two outputs share the path About/index.html and about/index.html",
    );
    await expect(
      writeSite(
        root,
        [
          { kind: "text", path: "a/index.html", content: "" },
          { kind: "copy", path: "A/index.html", source: join(root, "x") },
        ],
        [],
      ),
    ).rejects.toThrow("Two outputs share the path");
    expect(readFileSync(join(root, "dist/previous.html"), "utf8")).toBe("kept");
  });
});

describe("listStaticFiles", () => {
  async function titles(root: string): Promise<string[]> {
    const listed = await listStaticFiles(root);
    return listed.ok ? [] : listed.error.map(({ title }) => title);
  }

  test("lists nothing without a static folder", async () => {
    expect(await listStaticFiles(siteRoot())).toEqual({ ok: true, value: [] });
  });

  test("keeps hidden files and follows symlinks that stay inside the site", async () => {
    const root = siteRoot();
    mkdirSync(join(root, "static/.well-known"), { recursive: true });
    writeFileSync(join(root, "static/.well-known/security.txt"), "contact");
    mkdirSync(join(root, "assets/fonts"), { recursive: true });
    writeFileSync(join(root, "assets/fonts/a.woff2"), "font");
    writeFileSync(join(root, "assets/logo.svg"), "<svg/>");
    symlinkSync("../assets/fonts", join(root, "static/fonts"));
    symlinkSync("../assets/logo.svg", join(root, "static/logo.svg"));

    const listed = await listStaticFiles(root);

    if (!listed.ok) throw new Error("static/ should be listed");
    expect(listed.value.map(({ path }) => path)).toEqual([
      ".well-known/security.txt",
      "fonts/a.woff2",
      "logo.svg",
    ]);
  });

  test("refuses a symlink that leads outside the site", async () => {
    const outside = siteRoot();
    writeFileSync(join(outside, "id_ed25519"), "secret");
    const root = siteRoot();
    mkdirSync(join(root, "static"));
    symlinkSync(join(outside, "id_ed25519"), join(root, "static/key"));
    symlinkSync(outside, join(root, "static/home"));

    expect(await titles(root)).toEqual([
      "SYMLINK OUTSIDE SITE",
      "SYMLINK OUTSIDE SITE",
    ]);
  });

  test("refuses a static folder that is itself a symlink out of the site", async () => {
    const outside = siteRoot();
    writeFileSync(join(outside, "notes.txt"), "private");
    const root = siteRoot();
    symlinkSync(outside, join(root, "static"));

    expect(await titles(root)).toEqual(["SYMLINK OUTSIDE SITE"]);
  });

  test("reports a broken symlink instead of dropping the rest of static/", async () => {
    const root = siteRoot();
    mkdirSync(join(root, "static"));
    symlinkSync("missing.css", join(root, "static/a.css"));
    writeFileSync(join(root, "static/b.css"), "body {}");

    expect(await titles(root)).toEqual(["BROKEN SYMLINK"]);
  });

  test("reports a symlink to a folder that contains it", async () => {
    const root = siteRoot();
    mkdirSync(join(root, "static/nested"), { recursive: true });
    symlinkSync("..", join(root, "static/nested/up"));

    expect(await titles(root)).toEqual(["SYMLINK LOOP"]);
  });
});
