import { describe, expect, test } from "bun:test";
import { createHash } from "node:crypto";
import { mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { hashedPath, stylesheetCopies } from "../../src/emit/fingerprint";
import type { OutputFile } from "../../src/emit/write";

const bytes = new TextEncoder().encode("body { margin: 0 }");
const digest = createHash("sha256").update(bytes).digest("hex").slice(0, 8);

describe("hashedPath", () => {
  test("puts the first eight hex digits of the SHA-256 before the extension", () => {
    expect(hashedPath("style.css", bytes)).toBe(`style.${digest}.css`);
  });

  test("keeps the folder, and the dots of the name", () => {
    expect(hashedPath("css/site.css", bytes)).toBe(`css/site.${digest}.css`);
    expect(hashedPath("a.b.css", bytes)).toBe(`a.b.${digest}.css`);
  });

  test("changes with one byte and not otherwise", () => {
    const changed = bytes.slice();
    changed[0] = (changed[0] ?? 0) ^ 1;

    expect(hashedPath("style.css", changed)).not.toBe(
      hashedPath("style.css", bytes),
    );
    expect(hashedPath("style.css", bytes.slice())).toBe(
      hashedPath("style.css", bytes),
    );
  });
});

describe("stylesheetCopies", () => {
  test("makes one copy and stylesheet of each .css file, whatever its case, and ignores the rest", async () => {
    const folder = await mkdtemp(join(tmpdir(), "sheaf-fingerprint-"));
    const files: OutputFile[] = [];
    for (const path of ["style.css", "css/THEME.CSS", "favicon.svg", ".css"]) {
      const source = join(folder, path.replaceAll("/", "-"));
      await writeFile(source, bytes);
      files.push({ kind: "copy", path, source });
    }

    const { stylesheets, copies } = await stylesheetCopies(files);

    expect(stylesheets).toEqual([
      { path: "style.css", hashed: `style.${digest}.css` },
      { path: "css/THEME.CSS", hashed: `css/THEME.${digest}.CSS` },
    ]);
    expect(copies).toEqual([
      {
        kind: "copy",
        path: `style.${digest}.css`,
        source: join(folder, "style.css"),
      },
      {
        kind: "copy",
        path: `css/THEME.${digest}.CSS`,
        source: join(folder, "css-THEME.CSS"),
      },
    ]);
  });
});
