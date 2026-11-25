import { expect, test } from "bun:test";
import { decodeStarterFile, readStarter } from "../../scripts/embed-starter";
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

test("a starter file that is not text is refused by name", () => {
  expect(() =>
    decodeStarterFile(
      "static/logo.png",
      new Uint8Array([0x89, 0x50, 0xff, 0xfe]),
    ),
  ).toThrow("static/logo.png");
});
