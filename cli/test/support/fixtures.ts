import {
  cpSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const FIXTURES = join(import.meta.dir, "../fixtures");
const PACKAGE_SOURCE = join(import.meta.dir, "../../../src");

/** Where the fixtures live, for tests that build one in place. */
export function fixturePath(name: string): string {
  return join(FIXTURES, name);
}

const copies: string[] = [];

/**
 * Copies a fixture into a temporary directory so a test can change it. The
 * fixtures reach the Elm package with a path relative to their own folder,
 * which a copy elsewhere would break, so that entry is made absolute.
 */
export function copyFixture(name: string): string {
  const root = mkdtempSync(join(tmpdir(), `sheaf-${name}-`));
  copies.push(root);
  cpSync(fixturePath(name), root, {
    recursive: true,
    filter: (source) => !/[\\/](\.sheaf|dist|elm-stuff)$/.test(source),
  });

  const elmJsonPath = join(root, "elm.json");
  const elmJson = JSON.parse(readFileSync(elmJsonPath, "utf8"));
  elmJson["source-directories"] = elmJson["source-directories"].map(
    (directory: string) =>
      directory.endsWith("/src") && directory.startsWith("..")
        ? PACKAGE_SOURCE
        : directory,
  );
  writeFileSync(elmJsonPath, JSON.stringify(elmJson, null, 2));
  return root;
}

/** Deletes every copy made since the last call; for `afterEach`. */
export function removeFixtureCopies(): void {
  for (const root of copies.splice(0)) {
    rmSync(root, { recursive: true, force: true });
  }
}
