/**
 * Renders the images the README and the guide show: the starter's home page
 * and welcome post in both colour schemes, and the repository's social
 * preview. It builds a fresh site from this clone and photographs it with
 * Google Chrome in headless mode.
 *
 *     bun run screenshots
 *
 * Elm 0.19.3 must be on the PATH, since the site is built without installing
 * its dependencies. Chrome is looked for at its usual macOS location; set
 * `CHROME` to the path of its executable to use another.
 */
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { delimiter, join } from "node:path";
import { pathToFileURL } from "node:url";
import { inflateSync } from "node:zlib";

const REPO = join(import.meta.dir, "../..");
const CLI = join(REPO, "cli/src/index.ts");
const IMAGES = join(REPO, "docs/images");
const ASSETS = join(REPO, ".github/assets");
const MAX_BYTES = 300 * 1024;

const CHROME =
  process.env.CHROME ??
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";

type Scheme = "light" | "dark";

type Shot = {
  file: string;
  path: string;
  height: number;
  scheme: Scheme;
};

const SHOTS: Shot[] = [
  { file: "home-light.png", path: "/", height: 480, scheme: "light" },
  { file: "home-dark.png", path: "/", height: 480, scheme: "dark" },
  {
    file: "post-light.png",
    path: "/posts/welcome/",
    height: 1100,
    scheme: "light",
  },
  {
    file: "post-dark.png",
    path: "/posts/welcome/",
    height: 1100,
    scheme: "dark",
  },
];

/**
 * `bun run` puts the `node_modules/.bin` of this folder and of every folder
 * above it ahead of the PATH, where an Elm other than 0.19.3 may live. The
 * site is built with the PATH the script was started from instead.
 */
const PATH = (process.env.PATH ?? "")
  .split(delimiter)
  .filter((entry) => !entry.endsWith(join("node_modules", ".bin")))
  .join(delimiter);

async function run(command: string[], cwd: string): Promise<void> {
  const child = Bun.spawn(command, {
    cwd,
    env: { ...process.env, PATH },
    stdout: "pipe",
    stderr: "pipe",
  });
  const [code, stdout, stderr] = await Promise.all([
    child.exited,
    new Response(child.stdout).text(),
    new Response(child.stderr).text(),
  ]);
  if (code !== 0) {
    throw new Error(
      `${command.join(" ")} exited with ${code}\n${stdout}${stderr}`,
    );
  }
}

async function screenshot(
  url: string,
  output: string,
  size: { width: number; height: number },
  scheme: Scheme | undefined,
  profile: string,
): Promise<void> {
  const schemeFlags =
    scheme === "dark"
      ? ["--force-dark-mode", "--blink-settings=preferredColorScheme=0"]
      : scheme === "light"
        ? ["--blink-settings=preferredColorScheme=1"]
        : [];
  await run(
    [
      CHROME,
      "--headless",
      `--user-data-dir=${profile}`,
      `--screenshot=${output}`,
      `--window-size=${size.width},${size.height}`,
      "--hide-scrollbars",
      ...schemeFlags,
      url,
    ],
    REPO,
  );
}

/**
 * The relative luminance, from 0 to 1, of a PNG's top-left pixel. Whatever
 * filter the first row uses, its first pixel is stored unchanged, so no
 * unfiltering is needed.
 */
async function topLeftLuminance(path: string): Promise<number> {
  const png = Buffer.from(await Bun.file(path).arrayBuffer());
  const idat: Buffer[] = [];
  for (let offset = 8; offset < png.length; ) {
    const length = png.readUInt32BE(offset);
    const type = png.toString("ascii", offset + 4, offset + 8);
    if (type === "IDAT")
      idat.push(png.subarray(offset + 8, offset + 8 + length));
    offset += 12 + length;
  }
  const pixels = inflateSync(Buffer.concat(idat));
  const [red = 0, green = 0, blue = 0] = pixels.subarray(1, 4);
  return (0.2126 * red + 0.7152 * green + 0.0722 * blue) / 255;
}

async function check(path: string, scheme: Scheme | undefined): Promise<void> {
  const size = Bun.file(path).size;
  if (size >= MAX_BYTES) {
    throw new Error(`${path} is ${size} bytes, over the ${MAX_BYTES} limit`);
  }
  if (scheme === undefined) return;
  const luminance = await topLeftLuminance(path);
  if ((scheme === "dark") !== luminance < 0.5) {
    throw new Error(`${path} was meant to be ${scheme}, but it isn't`);
  }
}

async function main(): Promise<void> {
  const work = mkdtempSync(join(tmpdir(), "sheaf-screenshots-"));
  const site = join(work, "site");
  const profile = join(work, "chrome");
  try {
    await run([process.execPath, CLI, "init", site, "--local", REPO], REPO);
    await run([process.execPath, CLI, "build"], site);

    const dist = join(site, "dist");
    const server = Bun.serve({
      port: 0,
      hostname: "127.0.0.1",
      async fetch(request) {
        const { pathname } = new URL(request.url);
        const path = pathname.endsWith("/")
          ? `${pathname}index.html`
          : pathname;
        const file = Bun.file(join(dist, decodeURIComponent(path)));
        return (await file.exists())
          ? new Response(file)
          : new Response("Not found", { status: 404 });
      },
    });

    try {
      for (const shot of SHOTS) {
        const output = join(IMAGES, shot.file);
        await screenshot(
          new URL(shot.path, server.url).href,
          output,
          { width: 1280, height: shot.height },
          shot.scheme,
          profile,
        );
        await check(output, shot.scheme);
      }
    } finally {
      server.stop(true);
    }

    const preview = join(ASSETS, "social-preview.png");
    await screenshot(
      pathToFileURL(join(ASSETS, "social-preview.svg")).href,
      preview,
      { width: 1280, height: 640 },
      undefined,
      profile,
    );
    await check(preview, undefined);
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
}

await main();
