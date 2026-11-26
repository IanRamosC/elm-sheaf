import { afterAll, describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { bundleOptions, thirdPartyNotices } from "../../scripts/build-binaries";
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
      for (const name of [...EXCLUDED_GRAMMARS, ...EXCLUDED_THEMES]) {
        expect(entries).not.toContain(name);
        expect(noticeFiles).not.toContain(`${name}.json`);
      }
    },
    { timeout: 60_000 },
  );
});
