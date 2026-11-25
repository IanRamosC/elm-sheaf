import {
  cp,
  mkdir,
  readdir,
  readFile,
  rename,
  writeFile,
} from "node:fs/promises";
import { join, resolve } from "node:path";
import packageManifest from "../../package.json";
import { isErrno } from "../content/files";
import type { Diagnostic } from "../diagnostics/diagnostic";
import { err, ok, type Result } from "../result";
import { elmJson, packageJson } from "./project-files";

/** Plan 5 embeds this folder in the binaries. */
const STARTER = new URL("../../templates/default/", import.meta.url);

type InitOptions = {
  /** A checkout of the Sheaf repository to use instead of the published packages. */
  local: string | undefined;
  /** The date `{{today}}` becomes, as `YYYY-MM-DD`. */
  today: string;
};

/**
 * Creates a site from the starter. Everything that can fail is checked
 * before the first write, so a refused `init` leaves the folder as it was.
 */
export async function initSite(
  folder: string,
  { local, today }: InitOptions,
): Promise<Result<void, Diagnostic[]>> {
  const localRepository = local === undefined ? undefined : resolve(local);
  if (localRepository !== undefined) {
    const problem = await notASheafRepository(localRepository);
    if (problem !== undefined) return err([problem]);
  }
  // Bun on Windows fails to `mkdir` "." even with `recursive`, so every
  // write below goes to the absolute path.
  const target = resolve(folder);
  if (!(await isEmptyOrMissing(target))) {
    return err([
      {
        severity: "error",
        title: "FOLDER NOT EMPTY",
        message: `\`${folder}\` already has files in it, and \`sheaf init\` never overwrites.`,
        hint: "Pick a folder that is empty or doesn't exist yet.",
      },
    ]);
  }

  await mkdir(target, { recursive: true });
  await cp(STARTER, target, { recursive: true });
  // npm drops files named `.gitignore` from packages, so the starter stores it without the dot.
  await rename(join(target, "gitignore"), join(target, ".gitignore"));

  const welcome = join(target, "content/posts/welcome.md");
  await writeFile(
    welcome,
    (await readFile(welcome, "utf8")).replaceAll("{{today}}", today),
  );
  await writeFile(join(target, "elm.json"), elmJson(localRepository));
  await writeFile(
    join(target, "package.json"),
    packageJson(localRepository, packageManifest.version),
  );
  return ok(undefined);
}

/** A file in the way counts as not empty: `init` cannot make a folder there either. */
async function isEmptyOrMissing(folder: string): Promise<boolean> {
  try {
    return (await readdir(folder)).length === 0;
  } catch (error) {
    return isErrno(error) && error.code === "ENOENT";
  }
}

async function notASheafRepository(
  repository: string,
): Promise<Diagnostic | undefined> {
  const markers = ["src/Sheaf.elm", "cli/package.json"];
  const present = await Promise.all(
    markers.map((marker) => Bun.file(join(repository, marker)).exists()),
  );
  if (present.every(Boolean)) return undefined;
  return {
    severity: "error",
    title: "NOT A SHEAF REPOSITORY",
    message: `\`${repository}\` has no \`${markers.join("` and `")}\`.`,
    hint: "Point --local at a checkout of the Sheaf repository.",
  };
}
