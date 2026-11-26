import { afterAll, describe, expect, test } from "bun:test";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  bundleOptions,
  thirdPartyNotices,
  writeLicense,
} from "../../scripts/build-binaries";
import {
  EXCLUDED_GRAMMARS,
  EXCLUDED_THEMES,
} from "../../src/highlight/excluded";

const out = mkdtempSync(join(tmpdir(), "sheaf-bundle-"));

afterAll(() => rmSync(out, { recursive: true, force: true }));

/** The names of the grammars and themes listed, one per line, as `name (licence) source`. */
function entriesIn(notices: string): string[] {
  return notices
    .split("\n")
    .flatMap((line) => /^(\S+) \([^)]+\) https?:\/\//.exec(line)?.[1] ?? []);
}

/** Each grammar or theme line, as `name (licence) source`. */
function entryLines(notices: string): string[] {
  return notices
    .split("\n")
    .filter((line) => /^\S+ \([^)]+\) https?:\/\//.test(line));
}

describe("the binaries' notices", () => {
  test(
    "list no grammar or theme that Sheaf leaves out",
    async () => {
      const built = await Bun.build({ ...bundleOptions(), outdir: out });
      if (built.metafile === undefined) throw new Error("no metafile");

      const notices = await thirdPartyNotices(built.metafile);
      const entries = entriesIn(notices);
      const noticeFiles = [...notices.matchAll(/^Files:(.*)$/gm)].flatMap(
        ([, files = ""]) => files.split(",").map((file) => file.trim()),
      );

      expect(entries).toContain("elm");
      expect(entries).toContain("github-dark");
      expect(noticeFiles).toContain("elm.json");
      // A GPL grammar or theme added to Shiki must be left out too.
      expect(
        entryLines(notices).filter((line) => /\(A?GPL/.test(line)),
      ).toEqual([]);
      for (const name of [...EXCLUDED_GRAMMARS, ...EXCLUDED_THEMES]) {
        expect(entries).not.toContain(name);
        expect(noticeFiles).not.toContain(`${name}.json`);
      }
    },
    { timeout: 60_000 },
  );
});

describe("the binaries' licence", () => {
  test("is Sheaf's own LICENSE, copied next to them", async () => {
    await writeLicense(out);
    const license = readFileSync(join(out, "LICENSE"), "utf8");
    expect(license).toBe(
      readFileSync(join(import.meta.dir, "../../../LICENSE"), "utf8"),
    );
    expect(license).toContain("BSD 3-Clause");
  });
});
