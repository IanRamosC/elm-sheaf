/**
 * Compiles the CLI into a standalone binary for each system Sheaf supports,
 * and writes the licences of the npm packages bundled into them.
 *
 *     bun run build-binaries                         every target
 *     bun run build-binaries --target bun-linux-x64  one target
 *
 * Everything goes into `cli/out/`.
 */
import { mkdir, readdir, writeFile } from "node:fs/promises";
import { join, resolve, sep } from "node:path";
import { parseArgs } from "node:util";
import { grammars, injections } from "tm-grammars";
import { themes } from "tm-themes";
import {
  EXCLUDED_THEMES,
  excludedLanguageNames,
} from "../src/highlight/excluded";

export const TARGETS = [
  "bun-darwin-arm64",
  "bun-darwin-x64",
  "bun-linux-x64",
  "bun-linux-arm64",
  "bun-windows-x64",
] as const satisfies readonly Bun.Build.CompileTarget[];

export type Target = (typeof TARGETS)[number];

const cli = resolve(import.meta.dir, "..");
const out = join(cli, "out");

const BUN_LICENSING = "https://bun.com/docs/project/license";

/** `sheaf-<os>-<arch>`, with `.exe` on Windows. */
export function binaryName(target: Target): string {
  const name = target.replace(/^bun-/, "sheaf-");
  return target.startsWith("bun-windows-") ? `${name}.exe` : name;
}

/** The target that runs on this machine. */
export function hostTarget(): Target {
  const os = process.platform === "win32" ? "windows" : process.platform;
  const target = `bun-${os}-${process.arch}`;
  if (!isTarget(target)) {
    throw new Error(`Sheaf has no standalone binary for ${target}.`);
  }
  return target;
}

function isTarget(name: string): name is Target {
  return (TARGETS as readonly string[]).includes(name);
}

type Built = { binary: string; metafile: Bun.BuildMetafile };

/** Compiles the binary for `target` and gives its path. */
export async function buildBinary(target: Target): Promise<string> {
  return (await compile(target)).binary;
}

/**
 * Resolves Shiki's GPL-3.0 grammars and themes to a module of Sheaf's own, so
 * their files never enter the bundle. Shiki's lists still name them, and
 * loading one fails loudly, but Sheaf never asks for them.
 */
const leaveOutExcluded: Bun.BunPlugin = {
  name: "leave out excluded grammars and themes",
  setup(build) {
    const excluded = {
      langs: new Set(excludedLanguageNames()),
      themes: new Set(EXCLUDED_THEMES),
    };
    const namespace = "sheaf-excluded";
    build.onResolve(
      { filter: /^@shikijs\/(langs|themes)\/[\w.-]+$/ },
      ({ path }) => {
        const [, kind, name = ""] = path.split("/");
        const names = kind === "langs" ? excluded.langs : excluded.themes;
        return names.has(name) ? { path, namespace } : undefined;
      },
    );
    build.onLoad({ filter: /.*/, namespace }, ({ path }) => ({
      contents: `throw new Error(${JSON.stringify(`Sheaf leaves out ${path}, which is GPL-3.0.`)});`,
      loader: "js",
    }));
  },
};

/** What every build of the CLI shares, whatever it is compiled for. */
export function bundleOptions() {
  return {
    entrypoints: [join(cli, "src/index.ts")],
    target: "bun",
    plugins: [leaveOutExcluded],
    minify: true,
    metafile: true,
  } satisfies Bun.BuildConfig;
}

async function compile(target: Target): Promise<Built> {
  const binary = join(out, binaryName(target));
  const result = await Bun.build({
    ...bundleOptions(),
    compile: {
      target,
      outfile: binary,
      // A site's own .env or bunfig.toml is no business of Sheaf's.
      autoloadDotenv: false,
      autoloadBunfig: false,
    },
  });
  if (!result.success || result.metafile === undefined) {
    throw new AggregateError(result.logs, `Compiling ${target} failed`);
  }
  if (isMacTarget(target) && canSign()) await signAdHoc(binary);
  return { binary, metafile: result.metafile };
}

function isMacTarget(target: Target): boolean {
  return target.startsWith("bun-darwin-");
}

/** `codesign` comes with macOS only. */
function canSign(): boolean {
  return process.platform === "darwin";
}

/**
 * Replaces a macOS binary's signature with an ad-hoc one. A binary
 * cross-compiled for the other architecture keeps the signature of Bun's own
 * executable, which no longer matches once Sheaf is appended to it, and macOS
 * refuses to run a binary whose signature doesn't verify.
 */
async function signAdHoc(binary: string): Promise<void> {
  for (const command of [
    ["codesign", "--force", "--sign", "-", binary],
    ["codesign", "--verify", "--strict", binary],
  ]) {
    const child = Bun.spawn(command, { stdout: "ignore", stderr: "pipe" });
    const stderr = await new Response(child.stderr).text();
    if ((await child.exited) !== 0) {
      throw new Error(`${command.slice(0, 2).join(" ")} failed:\n${stderr}`);
    }
  }
}

type BundledPackage = {
  name: string;
  version: string;
  license: string;
  text: string;
};

/**
 * Every npm package with a file in the bundle, read from its folder in
 * `node_modules`. A package without a licence file stops the build, since
 * the binaries may not ship its code without the notice.
 */
async function bundledPackages(
  metafile: Bun.BuildMetafile,
): Promise<BundledPackage[]> {
  const folders = new Set<string>();
  for (const input of Object.keys(metafile.inputs)) {
    const folder = packageFolder(resolve(cli, input));
    if (folder !== undefined) folders.add(folder);
  }
  const packages = await Promise.all([...folders].map(readPackage));
  const unique = new Map(
    packages.map((found) => [`${found.name}@${found.version}`, found]),
  );
  return [...unique.values()].sort((a, b) => a.name.localeCompare(b.name));
}

/** The package folder a file is in: the last `node_modules` and the name after it. */
function packageFolder(file: string): string | undefined {
  const parts = file.split(sep);
  const modules = parts.lastIndexOf("node_modules");
  if (modules === -1) return undefined;
  const nameLength = parts[modules + 1]?.startsWith("@") ? 2 : 1;
  return parts.slice(0, modules + 1 + nameLength).join(sep);
}

async function readPackage(folder: string): Promise<BundledPackage> {
  const manifest: { name: string; version: string; license?: string } =
    await Bun.file(join(folder, "package.json")).json();
  const licenseFile = (await readdir(folder)).find((file) =>
    /^licen[cs]e(\.(md|txt))?$/i.test(file),
  );
  if (licenseFile === undefined) {
    throw new Error(`${manifest.name} has no licence file in ${folder}`);
  }
  return {
    name: manifest.name,
    version: manifest.version,
    license: manifest.license ?? "see below",
    text: (await Bun.file(join(folder, licenseFile)).text()).trim(),
  };
}

/** What tm-grammars and tm-themes record about each grammar and theme. */
type Upstream = { name: string; license?: string; source: string };

/**
 * The grammars and themes in the bundle. `@shikijs/langs` and
 * `@shikijs/themes` hold one file for each, built from tm-grammars and
 * tm-themes, which record where each came from and under which licence.
 * Their versions in package.json are the ones Shiki's own lockfile builds
 * from; a file with no record stops the build, as a missing licence does.
 */
function bundledUpstream(
  metafile: Bun.BuildMetafile,
  shikiPackage: "langs" | "themes",
  known: Upstream[],
): Upstream[] {
  const byName = new Map(known.map((entry) => [entry.name, entry]));
  const folder = `@shikijs/${shikiPackage}/dist/`;
  return Object.keys(metafile.inputs)
    .map((input) => input.split(sep).join("/"))
    .filter((input) => input.includes(folder) && input.endsWith(".mjs"))
    .map((input) => {
      const name = input.slice(input.lastIndexOf("/") + 1, -".mjs".length);
      const entry = byName.get(name);
      if (entry === undefined) {
        throw new Error(
          `${input} has no record in tm-grammars or tm-themes; check that their versions match Shiki's`,
        );
      }
      return entry;
    })
    .sort((a, b) => a.name.localeCompare(b.name));
}

type Collection = {
  title: string;
  packageName: string;
  version: string;
  entries: Upstream[];
  license: string;
  notice: string;
};

async function collection(
  title: string,
  packageName: "tm-grammars" | "tm-themes",
  entries: Upstream[],
): Promise<Collection> {
  // Read from the folder: neither package exports its package.json.
  const folder = join(cli, "node_modules", packageName);
  const manifest: { version: string } = await Bun.file(
    join(folder, "package.json"),
  ).json();
  return {
    title,
    packageName,
    version: manifest.version,
    entries,
    license: (await Bun.file(join(folder, "LICENSE")).text()).trim(),
    notice: noticeFor(
      (await Bun.file(join(folder, "NOTICE")).text()).trim(),
      entries,
    ),
  };
}

/**
 * The NOTICE of tm-grammars or tm-themes without the sections whose files are
 * all left out of the bundle, so it gives no licence for code Sheaf doesn't
 * carry. Each section starts with a rule and a `Files:` line.
 */
function noticeFor(notice: string, entries: Upstream[]): string {
  const bundled = new Set(entries.map(({ name }) => `${name}.json`));
  return notice
    .split(/\n(?==+\nFiles:)/)
    .filter((section) => {
      const files = /^=+\nFiles:(.*)$/m.exec(section)?.[1];
      return (
        files === undefined ||
        files.split(",").some((file) => bundled.has(file.trim()))
      );
    })
    .join("\n");
}

function thirdPartyLicenses(
  packages: BundledPackage[],
  collections: Collection[],
): string {
  const rule = "=".repeat(72);
  const sections = packages.map(
    ({ name, version, license, text }) =>
      `${rule}\n${name} ${version} (${license})\n${rule}\n\n${text}\n`,
  );
  const upstream = collections.map(
    ({ title, packageName, version, entries, license, notice }) =>
      [
        `${rule}\n${title}, from ${packageName} ${version}\n${rule}\n`,
        `Shiki's packages above carry these ${entries.length} ${title.toLowerCase()}, collected by ${packageName}. Each is under its own licence, named here with the place it comes from; "not stated" means its source names none. The licence and notices of ${packageName}, which give the full text of each one's licence, follow the list.\n`,
        ...entries.map(
          ({ name, license: spdx, source }) =>
            `${name} (${spdx ?? "not stated"}) ${source}`,
        ),
        `\n${packageName} licence:\n\n${license}\n\n${packageName} notices:\n\n${notice}\n`,
      ].join("\n"),
  );
  return [
    "Sheaf's standalone binaries contain the following npm packages, each under the licence that follows its name, and the grammars and themes listed after them.\n",
    ...sections,
    ...upstream,
    `${rule}\nBun\n${rule}\n\nThe binaries also contain Bun, the runtime they are compiled with. Bun's licence, and the licences of the libraries it includes, are at ${BUN_LICENSING}\n`,
  ].join("\n");
}

async function main(args: string[]): Promise<void> {
  const { values } = parseArgs({
    args,
    options: { target: { type: "string" } },
  });
  const requested = values.target;
  if (requested !== undefined && !isTarget(requested)) {
    throw new Error(
      `Unknown target ${requested}. Use one of: ${TARGETS.join(", ")}.`,
    );
  }
  await mkdir(out, { recursive: true });

  // The bundle is the same JavaScript for every target, so one metafile
  // lists the packages of them all.
  let metafile: Bun.BuildMetafile | undefined;
  for (const target of requested === undefined ? TARGETS : [requested]) {
    const built = await compile(target);
    metafile = built.metafile;
    const size = Bun.file(built.binary).size / 1024 / 1024;
    const unsigned =
      isMacTarget(target) && !canSign()
        ? "  (not re-signed: codesign needs macOS, so sign it there before release)"
        : "";
    process.stdout.write(
      `${binaryName(target)}  ${size.toFixed(1)} MB${unsigned}\n`,
    );
  }
  if (metafile === undefined) return;

  const { text, packages, collections } = await notices(metafile);
  await writeFile(join(out, "THIRD_PARTY_LICENSES"), text);
  const [grammarCount, themeCount] = collections.map(
    ({ entries }) => entries.length,
  );
  process.stdout.write(
    `THIRD_PARTY_LICENSES  ${packages.length} packages, ${grammarCount} grammars, ${themeCount} themes, and Bun\n`,
  );
}

/** The text of `THIRD_PARTY_LICENSES` for a bundle. */
export async function thirdPartyNotices(
  metafile: Bun.BuildMetafile,
): Promise<string> {
  return (await notices(metafile)).text;
}

async function notices(metafile: Bun.BuildMetafile): Promise<{
  text: string;
  packages: BundledPackage[];
  collections: Collection[];
}> {
  const packages = await bundledPackages(metafile);
  const collections = await Promise.all([
    collection(
      "Grammars",
      "tm-grammars",
      bundledUpstream(metafile, "langs", [...grammars, ...injections]),
    ),
    collection(
      "Themes",
      "tm-themes",
      bundledUpstream(metafile, "themes", themes),
    ),
  ]);
  return {
    text: thirdPartyLicenses(packages, collections),
    packages,
    collections,
  };
}

if (import.meta.main) await main(process.argv.slice(2));
