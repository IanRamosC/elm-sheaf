import { afterEach, describe, expect, test } from "bun:test";
import {
  existsSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join, sep } from "node:path";
import { initSite } from "../../src/init/init";

const REPO = join(import.meta.dir, "../../..");
const temporary: string[] = [];

function tempFolder(): string {
  const folder = mkdtempSync(join(tmpdir(), "sheaf-init-"));
  temporary.push(folder);
  return folder;
}

const titles = (result: Awaited<ReturnType<typeof initSite>>) =>
  result.ok ? [] : result.error.map(({ title }) => title);

afterEach(() => {
  for (const folder of temporary.splice(0)) {
    rmSync(folder, { recursive: true, force: true });
  }
});

describe("initSite", () => {
  test("refuses a folder holding only a hidden file, and leaves it alone", async () => {
    const folder = tempFolder();
    writeFileSync(join(folder, ".DS_Store"), "x");

    const result = await initSite(folder, {
      local: undefined,
      today: "2026-01-02",
    });

    expect(titles(result)).toEqual(["FOLDER NOT EMPTY"]);
    expect(readdirSync(folder)).toEqual([".DS_Store"]);
  });

  test("refuses a path that is a file", async () => {
    const folder = tempFolder();
    const file = join(folder, "file");
    writeFileSync(file, "x");

    const result = await initSite(file, {
      local: undefined,
      today: "2026-01-02",
    });

    expect(titles(result)).toEqual(["FOLDER NOT EMPTY"]);
  });

  test("creates a folder with spaces and non-ASCII characters", async () => {
    const folder = join(tempFolder(), "my blog é");

    const result = await initSite(folder, {
      local: undefined,
      today: "2026-01-02",
    });

    expect(result.ok).toBe(true);
    expect(existsSync(join(folder, ".gitignore"))).toBe(true);
    expect(existsSync(join(folder, "gitignore"))).toBe(false);
    expect(existsSync(join(folder, ".github/workflows/deploy.yml"))).toBe(true);
    expect(existsSync(join(folder, "elm.json"))).toBe(true);
    expect(existsSync(join(folder, "package.json"))).toBe(true);
    const welcome = readFileSync(
      join(folder, "content/posts/welcome.md"),
      "utf8",
    );
    expect(welcome).toContain("date: 2026-01-02");
    expect(welcome).not.toContain("{{today}}");
  });

  test("works in an empty folder that already exists", async () => {
    const folder = tempFolder();

    const result = await initSite(folder, {
      local: undefined,
      today: "2026-01-02",
    });

    expect(result.ok).toBe(true);
    expect(existsSync(join(folder, "sheaf.json"))).toBe(true);
  });

  test("refuses --local without a Sheaf repository, and writes nothing", async () => {
    const parent = tempFolder();
    const notRepo = tempFolder();
    const folder = join(parent, "site");

    const result = await initSite(folder, {
      local: notRepo,
      today: "2026-01-02",
    });

    expect(titles(result)).toEqual(["NOT A SHEAF REPOSITORY"]);
    expect(existsSync(folder)).toBe(false);
  });

  test("writes the repository's absolute paths with --local", async () => {
    const folder = join(tempFolder(), "site");

    const result = await initSite(folder, { local: REPO, today: "2026-01-02" });

    expect(result.ok).toBe(true);
    const elm = JSON.parse(readFileSync(join(folder, "elm.json"), "utf8"));
    const repo = REPO.split(sep).join("/");
    expect(elm["source-directories"]).toContain(`${repo}/src`);
    const npm = JSON.parse(readFileSync(join(folder, "package.json"), "utf8"));
    expect(npm.dependencies["elm-sheaf"]).toBe(`file:${repo}/cli`);
  });
});
