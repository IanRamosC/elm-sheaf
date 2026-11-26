import { describe, expect, test } from "bun:test";
import { checkElmPackage } from "../../src/elm/package-version";
import { elmJson as initElmJson } from "../../src/init/project-files";

function elmJson(
  dependency: string | undefined,
  sourceDirectories = ["src", ".sheaf/gen"],
): string {
  return JSON.stringify({
    type: "application",
    "source-directories": sourceDirectories,
    dependencies: {
      direct: {
        "elm/core": "1.0.5",
        ...(dependency === undefined
          ? {}
          : { "ianramosc/elm-sheaf": dependency }),
      },
      indirect: {},
    },
  });
}

const noLocal = () => false;
const localInSheafSrc = (directory: string) => directory === "/clone/src";

function titles(result: ReturnType<typeof checkElmPackage>): string[] {
  return result.ok ? [] : result.error.map(({ title }) => title);
}

describe("checkElmPackage", () => {
  test.each(["1.0.0", "1.4.2", "1.10.0"])("accepts version %s", (version) => {
    expect(checkElmPackage(elmJson(version), noLocal).ok).toBe(true);
  });

  test.each(["2.0.0", "1.0", "abc", "0.9.9"])(
    "rejects version %s",
    (version) => {
      const result = checkElmPackage(elmJson(version), noLocal);
      expect(titles(result)).toEqual(["UNSUPPORTED SHEAF VERSION"]);
      const [diagnostic] = result.ok ? [] : result.error;
      expect(diagnostic?.message).toContain(version);
      expect(diagnostic?.message).toContain("1.0.0 <= v < 2.0.0");
      expect(diagnostic?.hint).toContain(version);
    },
  );

  // Keeps the version init writes inside the range the CLI supports.
  test("accepts the elm.json init writes", () => {
    expect(checkElmPackage(initElmJson(undefined), noLocal).ok).toBe(true);
  });

  test("reports the dependency together with a local Sheaf.elm", () => {
    const result = checkElmPackage(
      elmJson("1.0.0", ["src", "/clone/src"]),
      localInSheafSrc,
    );
    expect(titles(result)).toEqual(["SHEAF PACKAGE TWICE"]);
  });

  test("accepts a local Sheaf.elm without the dependency", () => {
    const result = checkElmPackage(
      elmJson(undefined, ["src", "/clone/src"]),
      localInSheafSrc,
    );
    expect(result.ok).toBe(true);
  });

  test("reports neither the dependency nor a local Sheaf.elm", () => {
    const result = checkElmPackage(elmJson(undefined), noLocal);
    expect(titles(result)).toEqual(["SHEAF PACKAGE MISSING"]);
  });

  test("reports an elm.json that is not valid JSON", () => {
    const result = checkElmPackage('{ "type": "application", ', noLocal);
    expect(titles(result)).toEqual(["BAD ELM JSON"]);
  });

  test("reports a version that is not a string", () => {
    const text = elmJson("1.0.0").replace('"1.0.0"', "1");
    expect(titles(checkElmPackage(text, noLocal))).toEqual(["BAD ELM JSON"]);
  });

  test("reports an elm.json that is not an object", () => {
    expect(titles(checkElmPackage("[]", noLocal))).toEqual(["BAD ELM JSON"]);
  });
});
