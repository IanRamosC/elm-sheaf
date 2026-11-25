import { sep } from "node:path";

/** The Elm version Sheaf is built for; npm's `elm` tag for it is `0.19.3-0`. */
export const ELM_NPM_VERSION = "0.19.3-0";

/** The Elm package's version in the registry, which `--local` replaces with its source. */
const ELM_PACKAGE_VERSION = "1.0.0";

/**
 * The site's `elm.json`. A local checkout of Sheaf has no published package
 * to depend on, so its `src` joins the source directories instead.
 */
export function elmJson(local: string | undefined): string {
  const direct = {
    "elm/core": "1.0.5",
    "elm/json": "1.1.4",
    "elm/time": "1.0.0",
    ...(local === undefined
      ? { "ianramosc/elm-sheaf": ELM_PACKAGE_VERSION }
      : {}),
  };
  return formatted({
    type: "application",
    "source-directories": [
      "src",
      ".sheaf/gen",
      ...(local === undefined ? [] : [`${forwardSlashes(local)}/src`]),
    ],
    "elm-version": "0.19.3",
    dependencies: { direct, indirect: {} },
    "test-dependencies": { direct: {}, indirect: {} },
  });
}

/**
 * The site's `package.json`. `trustedDependencies` lets Bun run the `elm`
 * package's postinstall, which downloads the compiler; Bun skips the
 * postinstall of anything not listed.
 */
export function packageJson(
  local: string | undefined,
  cliVersion: string,
): string {
  return formatted({
    private: true,
    dependencies: {
      "elm-sheaf":
        local === undefined
          ? `^${cliVersion}`
          : `file:${forwardSlashes(local)}/cli`,
      elm: ELM_NPM_VERSION,
    },
    trustedDependencies: ["elm"],
  });
}

/** Windows accepts `/` too, so paths written into the site's files use it alone. */
function forwardSlashes(path: string): string {
  return path.split(sep).join("/");
}

function formatted(json: object): string {
  return `${JSON.stringify(json, null, 4)}\n`;
}
