/**
 * Runs axe on every page of a built site, once in the light colour scheme and
 * once in the dark one, and exits with 1 when it finds a violation.
 *
 *     bun audit.ts <dist folder>
 *
 * The pages are the ones `sitemap.xml` lists, plus `/404.html`. The folder is
 * served on a free local port, whatever host the sitemap names. Chrome is
 * looked for in its usual place on macOS and Linux; set `CHROME` to the path
 * of its executable to use another.
 */
import { join, resolve } from "node:path";
import type { AxeResults, Result } from "axe-core";
import puppeteer, { type Browser, type Page } from "puppeteer-core";

const TAGS = ["wcag2a", "wcag21a", "wcag2aa", "wcag21aa"];
const SCHEMES = ["light", "dark"] as const;

type Scheme = (typeof SCHEMES)[number];

type Violation = { path: string; scheme: Scheme; result: Result };

const DEFAULT_CHROME: Partial<Record<NodeJS.Platform, string>> = {
  darwin: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  linux: "/usr/bin/google-chrome",
};

class AuditFailure extends Error {}

function chromePath(): string {
  const path = process.env.CHROME ?? DEFAULT_CHROME[process.platform];
  if (path === undefined) {
    throw new AuditFailure(
      `No default Chrome location on ${process.platform}; set CHROME`,
    );
  }
  return path;
}

function serve(dist: string): ReturnType<typeof Bun.serve> {
  return Bun.serve({
    port: 0,
    hostname: "127.0.0.1",
    async fetch(request) {
      const { pathname } = new URL(request.url);
      const path = pathname.endsWith("/") ? `${pathname}index.html` : pathname;
      const file = Bun.file(join(dist, decodeURIComponent(path)));
      return (await file.exists())
        ? new Response(file)
        : new Response("Not found", { status: 404 });
    },
  });
}

/** The path of every `<loc>` in the sitemap, then the 404 page's. */
async function pagePaths(dist: string): Promise<string[]> {
  const sitemap = await Bun.file(join(dist, "sitemap.xml")).text();
  const paths = [...sitemap.matchAll(/<loc>([^<]+)<\/loc>/g)].map(
    ([, loc = ""]) => new URL(loc).pathname,
  );
  if (paths.length === 0) {
    throw new AuditFailure("sitemap.xml lists no pages");
  }
  return [...paths, "/404.html"];
}

async function open(page: Page, url: string, scheme: Scheme): Promise<void> {
  await page.emulateMediaFeatures([
    { name: "prefers-color-scheme", value: scheme },
  ]);
  const response = await page.goto(url, { waitUntil: "load" });
  if (response === null || !response.ok()) {
    throw new AuditFailure(
      `${url} answered ${response?.status() ?? "nothing"}`,
    );
  }
}

function bodyBackground(page: Page): Promise<string> {
  return page.evaluate(() => getComputedStyle(document.body).backgroundColor);
}

/**
 * Fails when both schemes give the home page the same background, which
 * would mean the emulation did nothing and light was audited twice.
 */
async function checkEmulation(page: Page, home: string): Promise<void> {
  await open(page, home, "light");
  const light = await bodyBackground(page);
  await open(page, home, "dark");
  const dark = await bodyBackground(page);
  if (light === dark) {
    throw new AuditFailure(
      `The home page's background is ${light} in both colour schemes, so the dark scheme isn't being emulated`,
    );
  }
}

async function audit(
  page: Page,
  url: string,
  scheme: Scheme,
  axeSource: string,
): Promise<Result[]> {
  await open(page, url, scheme);
  await page.addScriptTag({ content: axeSource });
  const results = await page.evaluate(
    (tags) =>
      (
        window as unknown as {
          axe: { run: (options: object) => Promise<AxeResults> };
        }
      ).axe.run({ runOnly: { type: "tag", values: tags } }),
    TAGS,
  );
  return results.violations;
}

function report(violations: Violation[]): string {
  return violations
    .map(({ path, scheme, result }) => {
      const nodes = result.nodes
        .map((node) =>
          `    ${node.target.join(" ")}\n      ${node.failureSummary ?? ""}`.trimEnd(),
        )
        .join("\n");
      return `${path} (${scheme}): ${result.id}, ${result.help}\n  ${result.helpUrl}\n${nodes}`;
    })
    .join("\n\n");
}

async function main(): Promise<number> {
  const [folder] = process.argv.slice(2);
  if (folder === undefined) {
    throw new AuditFailure("Usage: bun audit.ts <dist folder>");
  }
  const dist = resolve(folder);
  const axeSource = await Bun.file(
    Bun.resolveSync("axe-core/axe.min.js", import.meta.dir),
  ).text();
  const paths = await pagePaths(dist);

  const server = serve(dist);
  let browser: Browser | undefined;
  try {
    browser = await puppeteer.launch({
      executablePath: chromePath(),
      headless: true,
    });
    const page = await browser.newPage();
    await checkEmulation(page, new URL("/", server.url).href);

    const violations: Violation[] = [];
    for (const path of paths) {
      for (const scheme of SCHEMES) {
        const url = new URL(path, server.url).href;
        for (const result of await audit(page, url, scheme, axeSource)) {
          violations.push({ path, scheme, result });
        }
      }
    }

    const audited = `${paths.length} pages in ${SCHEMES.length} colour schemes`;
    if (violations.length > 0) {
      console.error(report(violations));
      console.error(`\n${violations.length} violations across ${audited}`);
      return 1;
    }
    console.log(`No violations across ${audited}`);
    return 0;
  } finally {
    await browser?.close();
    server.stop(true);
  }
}

try {
  process.exitCode = await main();
} catch (error) {
  if (!(error instanceof AuditFailure)) throw error;
  console.error(error.message);
  process.exitCode = 1;
}
