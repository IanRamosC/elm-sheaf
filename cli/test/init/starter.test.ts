import { expect, test } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { readStarter } from "../../scripts/embed-starter";
import { STARTER } from "../../src/init/starter.generated";

test("the embedded starter matches cli/templates/default", () => {
  const fresh = readStarter();
  expect([...STARTER.keys()], "Run `bun run embed-starter`.").toEqual([
    ...fresh.keys(),
  ]);
  for (const [path, text] of fresh) {
    expect(STARTER.get(path), `${path}: Run \`bun run embed-starter\`.`).toBe(
      text,
    );
  }
});

test("the welcome post carries the {{today}} placeholder", () => {
  expect(STARTER.get("content/posts/welcome.md")).toContain("{{today}}");
});

test("keeps gitignore under its npm-safe name", () => {
  expect(STARTER.has("gitignore")).toBe(true);
  expect(STARTER.has(".gitignore")).toBe(false);
});

test("a binary file in the starter folder fails with its name", () => {
  const folder = mkdtempSync(join(tmpdir(), "starter-"));
  try {
    writeFileSync(join(folder, "logo.png"), new Uint8Array([0x89, 0xff, 0xfe]));
    expect(() => readStarter(["logo.png"], folder)).toThrow("logo.png");
  } finally {
    rmSync(folder, { recursive: true });
  }
});
