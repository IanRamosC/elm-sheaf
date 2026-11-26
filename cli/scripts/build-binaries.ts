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

async function compile(target: Target): Promise<Built> {
  const binary = join(out, binaryName(target));
  const result = await Bun.build({
    entrypoints: [join(cli, "src/index.ts")],
    compile: {
      target,
      outfile: binary,
      // A site's own .env or bunfig.toml is no business of Sheaf's.
      autoloadDotenv: false,
      autoloadBunfig: false,
    },
    minify: true,
    metafile: true,
  });
  if (!result.success || result.metafile === undefined) {
    throw new AggregateError(result.logs, `Compiling ${target} failed`);
  }
  return { binary, metafile: result.metafile };
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

function thirdPartyLicenses(packages: BundledPackage[]): string {
  const rule = "=".repeat(72);
  const sections = packages.map(
    ({ name, version, license, text }) =>
      `${rule}\n${name} ${version} (${license})\n${rule}\n\n${text}\n`,
  );
  return [
    "Sheaf's standalone binaries contain the following npm packages, each under the licence that follows its name.\n",
    ...sections,
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
    process.stdout.write(`${binaryName(target)}  ${size.toFixed(1)} MB\n`);
  }
  if (metafile === undefined) return;

  const packages = await bundledPackages(metafile);
  await writeFile(
    join(out, "THIRD_PARTY_LICENSES"),
    thirdPartyLicenses(packages),
  );
  process.stdout.write(
    `THIRD_PARTY_LICENSES  ${packages.length} packages, and Bun\n`,
  );
}

if (import.meta.main) await main(process.argv.slice(2));
