import { afterEach, describe, expect, test } from "bun:test";
import {
  chmod,
  mkdir,
  mkdtemp,
  readdir,
  readFile,
  rm,
  stat,
  writeFile,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, dirname, join } from "node:path";
import type { Config } from "../../src/config/config";
import { listFiles } from "../../src/content/files";
import { loadContent } from "../../src/content/load";
import { imageOutputs } from "../../src/images/emit";
import {
  type ImageFile,
  pruneImageCache,
  resolveImages,
} from "../../src/images/resolve";
import { parseMarkdown } from "../../src/markdown/parse";
import type { Node } from "../../src/markdown/tree";
import {
  bmpBytes,
  gifBytes,
  jpegBytes,
  pngBytes,
  webpBytes,
} from "../support/images";

const config: Config = {
  siteUrl: new URL("https://example.com/"),
  basePath: "/",
  timezone: "UTC",
  highlight: { light: "github-light", dark: "github-dark" },
  images: { widths: [480, 960, 1600], formats: ["webp"] },
};

const roots: string[] = [];

afterEach(async () => {
  for (const root of roots.splice(0)) {
    await rm(root, { recursive: true, force: true });
  }
});

/** A site whose files are written from `files`, keyed by path relative to the root. */
async function site(files: Record<string, string | Uint8Array>) {
  const root = await mkdtemp(join(tmpdir(), "sheaf-images-"));
  roots.push(root);
  for (const [path, content] of Object.entries(files)) {
    await mkdir(dirname(join(root, path)), { recursive: true });
    await writeFile(join(root, path), content);
  }
  return root;
}

async function resolve(
  root: string,
  sourcePath: string,
  options: { config?: Config } = {},
) {
  const source = await readFile(join(root, sourcePath), "utf8");
  const loaded = loadContent(
    [{ path: sourcePath, source }],
    config,
    new Date("2026-11-24T00:00:00Z"),
    "production",
  );
  if (!loaded.ok) throw new Error(JSON.stringify(loaded.error));
  const [document] = loaded.value;
  if (document === undefined) throw new Error("no document");
  const tree = parseMarkdown(document);
  if (!tree.ok) throw new Error(JSON.stringify(tree.error));
  return resolveImages(
    tree.value,
    document,
    root,
    options.config ?? config,
    await listFiles(root, "content", "static"),
  );
}

async function resolved(root: string, sourcePath: string) {
  const result = await resolve(root, sourcePath);
  if (!result.ok) throw new Error(JSON.stringify(result.error, null, 2));
  return result.value;
}

async function problems(root: string, sourcePath: string) {
  const result = await resolve(root, sourcePath);
  if (result.ok) throw new Error("expected resolving to fail");
  return result.error;
}

function imagesIn(node: Node): Extract<Node, { type: "image" }>[] {
  if (node.type === "image") return [node];
  return "children" in node ? node.children.flatMap(imagesIn) : [];
}

function firstImage(tree: Node) {
  const [image] = imagesIn(tree);
  if (image === undefined) throw new Error("no image");
  return image;
}

const POST = "content/posts/a/index.md";

describe("resolveImages", () => {
  test("writes the original format and WebP at every width up to the original", async () => {
    const root = await site({
      [POST]: "![A photo](photo.png)\n",
      "content/posts/a/photo.png": pngBytes(1200, 800),
    });

    const { tree, files } = await resolved(root, POST);
    const { local } = firstImage(tree);

    expect(local?.src).toMatch(/^\/_sheaf\/images\/[0-9a-f]{16}-1200\.png$/);
    expect(local).toMatchObject({ width: 1200, height: 800 });
    expect(
      local?.variants.map(({ mediaType, files }) => ({
        mediaType,
        widths: files.map(({ width }) => width),
      })),
    ).toEqual([
      { mediaType: "image/png", widths: [480, 960, 1200] },
      { mediaType: "image/webp", widths: [480, 960, 1200] },
    ]);
    expect(files).toHaveLength(6);
    const small = files.find(({ path }) => path.endsWith("-480.webp"));
    if (small === undefined) throw new Error("no 480 WebP");
    const metadata = await new Bun.Image(
      await readFile(small.cached),
    ).metadata();
    expect(metadata).toEqual({ width: 480, height: 320, format: "webp" });
    expect(small.path).toBe(`${local?.src.slice(1, -9)}-480.webp`);
  });

  test("names variants after the format the bytes hold", async () => {
    const root = await site({
      [POST]: "![x](photo.png)\n",
      "content/posts/a/photo.png": await jpegBytes(400, 300),
    });

    const { local } = firstImage((await resolved(root, POST)).tree);

    expect(local?.src).toMatch(/-400\.jpg$/);
    expect(local?.variants[0]?.mediaType).toBe("image/jpeg");
  });

  test("writes a WebP source once per width", async () => {
    const root = await site({
      [POST]: "![x](photo.webp)\n",
      "content/posts/a/photo.webp": await webpBytes(1000, 500),
    });

    const { tree, files } = await resolved(root, POST);

    expect(firstImage(tree).local?.variants).toHaveLength(1);
    expect(files.map(({ path }) => path.replace(/^.*-/, ""))).toEqual([
      "480.webp",
      "960.webp",
      "1000.webp",
    ]);
  });

  test("gives one set of outputs for one image used twice, or two identical files", async () => {
    const photo = pngBytes(600, 400);
    const root = await site({
      [POST]: "![x](photo.png) ![y](copy.png)\n",
      "content/posts/b.md": "![x](a/photo.png)\n",
      "content/posts/a/photo.png": photo,
      "content/posts/a/copy.png": photo,
    });

    const first = await resolved(root, POST);
    const second = await resolved(root, "content/posts/b.md");
    const outputs = imageOutputs([...first.files, ...second.files]);

    expect(outputs).toHaveLength(4);
    expect(new Set(outputs.map(({ path }) => path)).size).toBe(4);
  });

  test("copies GIF and SVG files, reading their size", async () => {
    const svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 12"/>';
    const root = await site({
      [POST]: "![x](spinner.gif) ![y](icon.svg)\n",
      "content/posts/a/spinner.gif": gifBytes(),
      "content/posts/a/icon.svg": svg,
    });

    const { tree, files } = await resolved(root, POST);
    const [gif, icon] = imagesIn(tree);

    expect(gif?.local).toMatchObject({ width: 1, height: 1, variants: [] });
    expect(icon?.local).toMatchObject({ width: 24, height: 12, variants: [] });
    expect(icon?.local?.src).toMatch(/-24\.svg$/);
    const copied = files.find(({ path }) => path.endsWith(".svg"));
    expect(copied && (await readFile(copied.cached, "utf8"))).toBe(svg);
  });

  test("finds percent-encoded, accented and decomposed names", async () => {
    const root = await site({
      [POST]: "![x](my%20photo.png) ![y](café.png) ![z](ação.png)\n",
      "content/posts/a/my photo.png": pngBytes(10, 10),
      "content/posts/a/café.png": pngBytes(10, 10),
      ["content/posts/a/ação.png".normalize("NFD")]: pngBytes(10, 10),
    });

    const { tree } = await resolved(root, POST);

    expect(imagesIn(tree).every(({ local }) => local !== undefined)).toBe(true);
  });

  test("reads an image starting with / from static/", async () => {
    const root = await site({
      [POST]: "![Logo](/logo.png)\n",
      "static/logo.png": pngBytes(64, 32),
    });

    const { tree } = await resolved(root, POST);

    expect(firstImage(tree).local).toMatchObject({ width: 64, height: 32 });
  });

  test("leaves remote and data images alone", async () => {
    const markdown =
      "![a](https://example.com/a.png) ![b](//cdn.example.com/b.png) ![c](data:image/png;base64,AAAA)\n";
    const root = await site({ [POST]: markdown });

    const { tree, files } = await resolved(root, POST);

    expect(imagesIn(tree).map(({ local }) => local)).toEqual([
      undefined,
      undefined,
      undefined,
    ]);
    expect(files).toEqual([]);
  });

  test("rejects images outside content/ and static/", async () => {
    const root = await site({
      [POST]: "![x](../../../outside.png)\n\n![y](/../x.png)\n",
      "outside.png": pngBytes(10, 10),
      "x.png": pngBytes(10, 10),
    });

    const [relative, rooted] = await problems(root, POST);

    expect(relative).toMatchObject({
      title: "IMAGE OUTSIDE FOLDER",
      sourcePath: POST,
      span: { start: { line: 1, column: 1 } },
    });
    expect(rooted).toMatchObject({
      title: "IMAGE OUTSIDE FOLDER",
      span: { start: { line: 3, column: 1 } },
    });
  });

  test("reports a name that differs only in case", async () => {
    const root = await site({
      [POST]: "![x](Photo.PNG)\n",
      "content/posts/a/photo.png": pngBytes(10, 10),
    });

    expect(await problems(root, POST)).toMatchObject([
      {
        title: "CASE MISMATCH",
        message:
          "The file is `photo.png`, but this refers to `Photo.PNG`. Linux treats them as different files, so the site would fail to build there.",
      },
    ]);
  });

  test("suggests a close name for a missing image", async () => {
    const root = await site({
      [POST]: "![x](phot.png)\n",
      "content/posts/a/photo.png": pngBytes(10, 10),
    });

    expect(await problems(root, POST)).toMatchObject([
      { title: "MISSING IMAGE", hint: "Did you mean `photo.png`?" },
    ]);
  });

  test("names the formats it publishes for any other kind of image", async () => {
    const root = await site({
      [POST]: "![x](old.bmp)\n",
      "content/posts/a/old.bmp": bmpBytes(),
    });

    const [problem] = await problems(root, POST);

    expect(problem?.title).toBe("UNSUPPORTED IMAGE");
    expect(problem?.hint).toContain("JPEG, PNG, WebP, GIF or SVG");
  });

  test("rejects a truncated image whose header still reads", async () => {
    const photo = pngBytes(1200, 800);
    const truncated = photo.subarray(0, Math.floor(photo.length * 0.6));
    expect(await new Bun.Image(truncated).metadata()).toMatchObject({
      width: 1200,
    });
    const root = await site({
      [POST]: "Text.\n\n![x](photo.png)\n",
      "content/posts/a/photo.png": truncated,
    });

    expect(await problems(root, POST)).toMatchObject([
      { title: "BAD IMAGE", span: { start: { line: 3, column: 1 } } },
    ]);
    expect(await cachedNames(root)).toEqual([]);
  });

  test("rejects an SVG without a size", async () => {
    const root = await site({
      [POST]: "![x](icon.svg)\n",
      "content/posts/a/icon.svg": "<svg><path/></svg>",
    });

    expect(await problems(root, POST)).toMatchObject([
      { title: "SVG WITHOUT SIZE" },
    ]);
  });

  test("resolves the cover image in both forms", async () => {
    for (const frontmatter of [
      "image: cover.png",
      "image: { src: cover.png, alt: Cover }",
    ]) {
      const root = await site({
        [POST]: `---\n${frontmatter}\n---\nBody.\n`,
        "content/posts/a/cover.png": pngBytes(800, 400),
      });

      const { image, files } = await resolved(root, POST);

      expect(image?.url).toBe("cover.png");
      expect(image?.local).toMatchObject({ width: 800, height: 400 });
      expect(files).toHaveLength(4);
    }
  });

  test("keeps a remote cover image as it is", async () => {
    const root = await site({
      [POST]: "---\nimage: { src: 'https://example.com/a.png', alt: A }\n---\n",
    });

    expect((await resolved(root, POST)).image).toEqual({
      url: "https://example.com/a.png",
      alt: "A",
    });
  });

  test("points a missing cover image at the image key", async () => {
    const root = await site({
      [POST]: "---\ntitle: A\nimage: cover.png\n---\n",
    });

    expect(await problems(root, POST)).toMatchObject([
      {
        title: "MISSING IMAGE",
        span: { start: { line: 3, column: 1 }, end: { line: 3, column: 6 } },
      },
    ]);
  });
});

async function cachedNames(root: string): Promise<string[]> {
  try {
    return (await readdir(join(root, ".sheaf/cache/images"))).sort();
  } catch {
    return [];
  }
}

describe("the image cache", () => {
  test("encodes an image once", async () => {
    const root = await site({
      [POST]: "![x](photo.png)\n",
      "content/posts/a/photo.png": pngBytes(600, 400),
    });

    const first = await resolved(root, POST);
    const before = await Promise.all(first.files.map(fileIdentity));
    const second = await resolved(root, POST);
    const after = await Promise.all(second.files.map(fileIdentity));

    expect(second.files).toEqual(first.files);
    expect(after).toEqual(before);
  });

  test("never uses a file left behind by an interrupted write", async () => {
    const root = await site({
      [POST]: "![x](photo.png)\n",
      "content/posts/a/photo.png": pngBytes(600, 400),
    });
    const { files } = await resolved(root, POST);
    const [file] = files;
    if (file === undefined) throw new Error("no file");
    const leftover = `${file.cached}.interrupted.tmp`;
    await writeFile(leftover, "half");
    await rm(file.cached);

    const again = await resolved(root, POST);

    for (const { cached } of again.files) {
      expect(cached.endsWith(".tmp")).toBe(false);
      await new Bun.Image(await readFile(cached)).png().bytes();
    }
    expect(
      (await cachedNames(root)).filter((name) => name.endsWith(".tmp")),
    ).toEqual([basename(leftover)]);
  });
});

async function fileIdentity({ cached }: ImageFile) {
  const { ino, mtimeMs } = await stat(cached);
  return { ino, mtimeMs };
}

describe("cache upkeep", () => {
  test("pruning keeps the files in use and deletes the rest", async () => {
    const root = await site({
      [POST]: "![x](photo.png)\n",
      "content/posts/a/photo.png": pngBytes(600, 400),
    });
    const { files } = await resolved(root, POST);
    const stale = join(root, ".sheaf/cache/images/0000-480.webp");
    await writeFile(stale, "old");

    await pruneImageCache(root, files);

    expect(await cachedNames(root)).toEqual(
      files.map(({ cached }) => basename(cached)).sort(),
    );
  });

  test("pruning a site with no cache does nothing", async () => {
    const root = await site({});

    await pruneImageCache(root, []);

    expect(await cachedNames(root)).toEqual([]);
  });

  test("reports a cache that is not a folder", async () => {
    const root = await site({
      [POST]: "![x](photo.png)\n",
      "content/posts/a/photo.png": pngBytes(600, 400),
      ".sheaf/cache/images": "not a folder",
    });

    expect(await problems(root, POST)).toMatchObject([
      {
        title: "CACHE NOT WRITABLE",
        span: { start: { line: 1, column: 1 } },
      },
    ]);
  });

  test.skipIf(process.getuid?.() === 0)(
    "reports an image that cannot be read",
    async () => {
      const root = await site({
        [POST]: "Text.\n\n![x](photo.png)\n",
        "content/posts/a/photo.png": pngBytes(600, 400),
      });
      const photo = join(root, "content/posts/a/photo.png");
      await chmod(photo, 0o000);

      try {
        expect(await problems(root, POST)).toMatchObject([
          {
            title: "IMAGE NOT READABLE",
            span: { start: { line: 3, column: 1 } },
          },
        ]);
      } finally {
        await chmod(photo, 0o644);
      }
    },
  );
});
