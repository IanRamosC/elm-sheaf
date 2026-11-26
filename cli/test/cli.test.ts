import { afterEach, describe, expect, test } from "bun:test";
import {
  appendFileSync,
  existsSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import packageJson from "../package.json";
import { unsupportedBun } from "../src/cli/main";
import {
  copyFixture,
  fixturePath,
  removeFixtureCopies,
} from "./support/fixtures";

const ENTRY = join(import.meta.dir, "../src/index.ts");
const SLOW = 60_000;

async function sheaf(args: string[], cwd: string) {
  const child = Bun.spawn([process.execPath, ENTRY, ...args], {
    cwd,
    stdout: "pipe",
    stderr: "pipe",
    env: { ...process.env, NO_COLOR: "1" },
  });
  const [stdout, stderr, exitCode] = await Promise.all([
    new Response(child.stdout).text(),
    new Response(child.stderr).text(),
    child.exited,
  ]);
  return { stdout, stderr, exitCode };
}

const copies: string[] = [];

afterEach(() => {
  removeFixtureCopies();
  for (const folder of copies.splice(0)) {
    rmSync(folder, { recursive: true, force: true });
  }
});

/** A running `sheaf dev`, whose output is collected as it arrives. */
function startDev(cwd: string) {
  const child = Bun.spawn([process.execPath, ENTRY, "dev", "--port", "0"], {
    cwd,
    stdout: "pipe",
    stderr: "pipe",
    env: { ...process.env, NO_COLOR: "1" },
  });
  let output = "";
  const decoder = new TextDecoder();
  void (async () => {
    for await (const chunk of child.stdout) {
      output += decoder.decode(chunk, { stream: true });
    }
  })();

  const occurrences = (pattern: RegExp) =>
    output.match(new RegExp(pattern.source, "gm"))?.length ?? 0;

  /** Waits until `pattern` has matched `times` lines of the output. */
  async function waitFor(pattern: RegExp, times = 1): Promise<void> {
    const deadline = performance.now() + SLOW / 2;
    while (occurrences(pattern) < times) {
      if (performance.now() > deadline || child.exitCode !== null) {
        const stderr = await new Response(child.stderr).text();
        throw new Error(
          `Expected ${times} × ${pattern} in:\n${output}\nstderr:\n${stderr}`,
        );
      }
      await Bun.sleep(20);
    }
  }

  /** Waits until a second passes without new output, as when the builds have caught up. */
  async function waitForQuiet(): Promise<void> {
    let seen = "";
    while (seen !== output) {
      seen = output;
      await Bun.sleep(1000);
    }
  }

  return {
    child,
    output: () => output,
    occurrences,
    waitFor,
    waitForQuiet,
  };
}

describe("sheaf", () => {
  test(
    "build succeeds on a valid site and says how many pages",
    async () => {
      const { stdout, exitCode } = await sheaf(
        ["build"],
        fixturePath("minimal"),
      );

      expect(exitCode).toBe(0);
      expect(stdout).toMatch(/Built 1 page in \d+\.\d+s/);
    },
    SLOW,
  );

  test(
    "build --site-url writes that address into the sitemap",
    async () => {
      const root = copyFixture("minimal");

      const { exitCode } = await sheaf(
        ["build", "--site-url", "https://x.example/sub/"],
        root,
      );

      expect(exitCode).toBe(0);
      expect(readFileSync(join(root, "dist/sitemap.xml"), "utf8")).toContain(
        "https://x.example/sub/",
      );
    },
    SLOW,
  );

  test(
    "check fails with the diagnostics and a count",
    async () => {
      const { stdout, exitCode } = await sheaf(
        ["check"],
        fixturePath("broken-links"),
      );

      expect(exitCode).toBe(1);
      expect(stdout).toContain("-- BROKEN LINK ---");
      expect(stdout).toContain("content/posts/2026-11-23-hello-world.md:5:6");
      expect(stdout).toContain("^^^^");
      expect(stdout).toContain("Found 2 errors");
    },
    SLOW,
  );

  test(
    "check names a misspelled frontmatter key and suggests the right one",
    async () => {
      const root = copyFixture("minimal");
      const post = join(root, "content/posts/2026-11-23-hello-world.md");
      writeFileSync(
        post,
        readFileSync(post, "utf8").replace("title:", "titel:"),
      );

      const { stdout, exitCode } = await sheaf(["check"], root);

      expect(exitCode).toBe(1);
      expect(stdout).toContain("-- UNKNOWN FIELD ---");
      expect(stdout).toContain("Did you mean `title`?");
    },
    SLOW,
  );

  test(
    "dev serves drafts, rebuilds on changes and shows errors",
    async () => {
      const root = copyFixture("blog");
      const posts = join(root, "content/posts");
      const site = join(root, "src/Site.elm");
      const dev = startDev(root);
      try {
        await dev.waitFor(/^Serving at /);
        const url = dev.output().match(/^Serving at (\S+)/m)?.[1] ?? "";
        expect(url).toMatch(/^http:\/\/127\.0\.0\.1:\d+\/blog\/$/);
        await dev.waitFor(/^Rebuilt \d+ pages and 1 redirect in \d+\.\d+s/);

        const home = await (await fetch(url)).text();
        expect(home).toContain("Plans");
        expect(home).toContain('<script type="module">');
        expect(dev.output()).not.toContain("Compiled in DEV mode");

        appendFileSync(
          join(posts, "2026-11-01-hello-sheaf.md"),
          "\nA sentence added while serving.\n",
        );
        await dev.waitFor(/^Rebuilt/, 2);
        const post = await (await fetch(`${url}posts/hello-sheaf/`)).text();
        expect(post).toContain("A sentence added while serving.");

        // Every build rewrites .sheaf/, which must not start another one.
        await Bun.sleep(1000);
        expect(dev.occurrences(/^Rebuilt/)).toBe(2);

        const original = readFileSync(site, "utf8");
        writeFileSync(site, `${original}\nbroken =\n`);
        await dev.waitFor(/^Found \d+ errors?/);
        const failed = await fetch(url);
        expect(failed.status).toBe(500);
        expect(await failed.text()).toContain("src/Site.elm");

        writeFileSync(site, original);
        await dev.waitFor(/^Rebuilt/, 3);
        expect((await fetch(url)).status).toBe(200);

        for (const name of [
          "2026-11-01-hello-sheaf.md",
          "2026-11-05-typed-templates.md",
          "2026-11-10-formatting.md",
          "2026-11-15-feeds.md",
          "2026-11-20-tags-and-groups.md",
        ]) {
          appendFileSync(join(posts, name), "\nOne more line.\n");
        }
        await dev.waitFor(/^Rebuilt/, 4);
        await Bun.sleep(1000);
        expect(dev.occurrences(/^Rebuilt/)).toBe(4);

        for (let edit = 0; edit < 10; edit++) {
          appendFileSync(
            join(posts, "2026-11-15-feeds.md"),
            `\nEdit ${edit}.\n`,
          );
          if (edit === 5) {
            rmSync(join(posts, "2026-11-05-typed-templates.md"));
          }
          await Bun.sleep(30);
        }
        await dev.waitForQuiet();
        expect((await fetch(url)).status).toBe(200);

        expect(existsSync(join(root, "dist"))).toBe(false);
        const output = join(root, ".sheaf/dev", String(dev.child.pid));
        expect(existsSync(output)).toBe(true);

        if (process.platform === "win32") {
          // Windows has no SIGTERM: kill() ends `dev` at once, before it can
          // clean up, so the next `dev` on the site removes what it left.
          dev.child.kill();
          await dev.child.exited;
          expect(existsSync(output)).toBe(true);
          const next = startDev(root);
          try {
            await next.waitFor(/^Rebuilt/);
            expect(existsSync(output)).toBe(false);
          } finally {
            next.child.kill();
            await next.child.exited;
          }
        } else {
          dev.child.kill("SIGTERM");
          expect(await dev.child.exited).toBe(0);
          expect(existsSync(output)).toBe(false);
        }
      } finally {
        dev.child.kill();
      }
    },
    SLOW * 2,
  );

  test("dev rejects options of other commands and a bad port", async () => {
    for (const args of [
      ["dev", "--port", "abc"],
      ["dev", "--port", "65536"],
      ["dev", "--drafts"],
      ["dev", "--site-url", "https://x.example/"],
      ["build", "--port", "1"],
      ["build", "--local", "/repo"],
      ["init", "site", "--drafts"],
      ["init", "site", "--port", "1"],
      ["init"],
      ["init", "one", "two"],
    ]) {
      const { stderr, exitCode } = await sheaf(args, import.meta.dir);

      expect(exitCode).toBe(2);
      expect(stderr).toContain("Usage:");
    }
  });

  test("init in the current empty folder prints the next steps", async () => {
    const folder = mkdtempSync(join(tmpdir(), "sheaf-init-cli-"));
    copies.push(folder);

    const { stdout, stderr, exitCode } = await sheaf(["init", "."], folder);

    expect({ exitCode, stderr, stdout }).toMatchObject({
      exitCode: 0,
      stderr: "",
    });
    expect(existsSync(join(folder, "sheaf.json"))).toBe(true);
    expect(stdout).toContain("bun install");
    expect(stdout).toContain("bunx sheaf dev");
    expect(stdout).not.toContain("cd ");
  });

  test("init refuses a folder with files in it", async () => {
    const folder = mkdtempSync(join(tmpdir(), "sheaf-init-cli-"));
    copies.push(folder);
    writeFileSync(join(folder, ".DS_Store"), "x");

    const { stdout, exitCode } = await sheaf(["init", "."], folder);

    expect(exitCode).toBe(1);
    expect(stdout).toContain("FOLDER NOT EMPTY");
  });

  test(
    "init --local makes a site that builds",
    async () => {
      const parent = mkdtempSync(join(tmpdir(), "sheaf-init-cli-"));
      copies.push(parent);
      const site = join(parent, "my blog");

      const created = await sheaf(
        ["init", site, "--local", join(import.meta.dir, "../..")],
        parent,
      );
      const built = await sheaf(["build"], site);

      expect(created.exitCode).toBe(0);
      expect(created.stdout.trimEnd().split("\n").slice(-4)).toEqual([
        "Next steps:",
        `  cd '${site}'`,
        "  bun install",
        "  bunx sheaf dev",
      ]);
      expect(built.stdout).toContain("Built");
      expect(built.exitCode).toBe(0);
      expect(existsSync(join(site, "dist/index.html"))).toBe(true);
    },
    SLOW,
  );

  test("prints help and exits 2 for an unknown command", async () => {
    const { stderr, exitCode } = await sheaf(["frobnicate"], import.meta.dir);

    expect(exitCode).toBe(2);
    expect(stderr).toContain("Usage:");
  });

  test("prints help for --help", async () => {
    const { stdout, exitCode } = await sheaf(["--help"], import.meta.dir);

    expect(exitCode).toBe(0);
    expect(stdout).toContain("sheaf build");
  });

  test("prints the package version", async () => {
    const { stdout, exitCode } = await sheaf(["--version"], import.meta.dir);

    expect(exitCode).toBe(0);
    expect(stdout.trim()).toBe(packageJson.version);
  });
});

describe("unsupportedBun", () => {
  test("accepts the floor and anything newer", () => {
    expect(unsupportedBun("1.4.5", ">=1.4.5")).toBeUndefined();
    expect(unsupportedBun("1.5.0", ">=1.4.5")).toBeUndefined();
  });

  test("names both versions when Bun is too old", () => {
    expect(unsupportedBun("1.3.9", ">=1.4.5")).toBe(
      "Sheaf needs Bun >=1.4.5, but this is Bun 1.3.9. Run `bun upgrade` to update it.",
    );
  });
});
