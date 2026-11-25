import { describe, expect, test } from "bun:test";
import { elmJson, packageJson } from "../../src/init/project-files";

describe("elmJson", () => {
  test("depends on the published package without --local", () => {
    const json = JSON.parse(elmJson(undefined));
    expect(json["source-directories"]).toEqual(["src", ".sheaf/gen"]);
    expect(json.dependencies.direct).toEqual({
      "elm/core": "1.0.5",
      "elm/json": "1.1.4",
      "elm/time": "1.0.0",
      "ianramosc/elm-sheaf": "1.0.0",
    });
  });

  test("reads the package's source from the repository with --local", () => {
    const json = JSON.parse(elmJson("/repo"));
    expect(json["source-directories"]).toEqual([
      "src",
      ".sheaf/gen",
      "/repo/src",
    ]);
    expect(json.dependencies.direct).not.toHaveProperty("ianramosc/elm-sheaf");
  });

  test("is formatted with a final newline", () => {
    expect(elmJson(undefined)).toEndWith("}\n");
    expect(elmJson(undefined)).toContain('\n    "type": "application"');
  });
});

describe("packageJson", () => {
  test("points elm-sheaf at the repository's cli folder with --local", () => {
    const json = JSON.parse(packageJson("/repo", "0.1.0"));
    expect(json.dependencies).toEqual({
      "elm-sheaf": "file:/repo/cli",
      elm: "0.19.3-0",
    });
    expect(json.private).toBe(true);
  });

  test("asks for the running CLI's version otherwise", () => {
    const json = JSON.parse(packageJson(undefined, "0.1.0"));
    expect(json.dependencies["elm-sheaf"]).toBe("^0.1.0");
  });

  test("trusts elm so that bun runs the postinstall that downloads it", () => {
    const json = JSON.parse(packageJson(undefined, "0.1.0"));
    expect(json.trustedDependencies).toEqual(["elm"]);
    expect(packageJson(undefined, "0.1.0")).toEndWith("}\n");
  });
});
