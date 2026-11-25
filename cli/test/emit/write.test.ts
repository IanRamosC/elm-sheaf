import { afterEach, describe, expect, test } from "bun:test";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { writeSite } from "../../src/emit/write";

const roots: string[] = [];

afterEach(async () => {
  for (const root of roots.splice(0)) {
    await rm(root, { recursive: true, force: true });
  }
});

async function siteRoot() {
  const root = await mkdtemp(join(tmpdir(), "sheaf-write-"));
  roots.push(root);
  return root;
}

describe("writeSite", () => {
  test("writes text outputs and copies files", async () => {
    const root = await siteRoot();
    const source = join(root, "photo.webp");
    await writeFile(source, "image bytes");

    await writeSite(root, [
      { kind: "text", path: "index.html", content: "<p>Hi</p>" },
      { kind: "copy", path: "_sheaf/images/h-480.webp", source },
    ]);

    expect(await readFile(join(root, "dist/index.html"), "utf8")).toBe(
      "<p>Hi</p>",
    );
    expect(
      await readFile(join(root, "dist/_sheaf/images/h-480.webp"), "utf8"),
    ).toBe("image bytes");
  });

  test("refuses a copy that clashes with a page", async () => {
    const root = await siteRoot();

    expect(
      writeSite(root, [
        { kind: "text", path: "a/index.html", content: "" },
        { kind: "copy", path: "A/index.html", source: join(root, "x") },
      ]),
    ).rejects.toThrow("Two outputs share the path");
  });
});
