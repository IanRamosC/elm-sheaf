import { beforeAll, describe, expect, test } from "bun:test";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { splitFrontmatter } from "../src/content/frontmatter";
import { HeadingIds } from "../src/markdown/heading-id";

const REPO = join(import.meta.dir, "../..");
const ENTRY = join(import.meta.dir, "../src/index.ts");
const GUIDE = join(REPO, "docs/content/guide");

function read(path: string): string {
  return readFileSync(path, "utf8");
}

function guidePages(): string[] {
  if (!existsSync(GUIDE)) return [];
  return readdirSync(GUIDE)
    .filter((name) => name.endsWith(".md"))
    .sort()
    .map((name) => join(GUIDE, name));
}

type Page = {
  data: Record<string, unknown>;
  body: string;
};

function guidePage(path: string): Page {
  const split = splitFrontmatter(read(path), path);
  if (!split.ok) throw new Error(`${path} has invalid frontmatter`);
  return split.value;
}

function filesUnder(directory: string, extension: string): string[] {
  return readdirSync(directory, { recursive: true, encoding: "utf8" })
    .filter((path) => path.endsWith(extension))
    .map((path) => join(directory, path));
}

/** A Markdown file split into its prose lines and its fenced code blocks. */
type Markdown = { prose: string[]; codeBlocks: string[][] };

function splitMarkdown(text: string): Markdown {
  const prose: string[] = [];
  const codeBlocks: string[][] = [];
  let fence: string | undefined;
  let block: string[] = [];
  for (const line of text.split("\n")) {
    const opening = /^\s*(`{3,}|~{3,})/.exec(line)?.[1];
    if (fence === undefined && opening !== undefined) {
      fence = opening;
      block = [];
    } else if (fence !== undefined && line.trim().startsWith(fence)) {
      codeBlocks.push(block);
      fence = undefined;
    } else if (fence !== undefined) {
      block.push(line);
    } else {
      prose.push(line);
    }
  }
  return { prose, codeBlocks };
}

/**
 * A diagnostic title is written in capitals, two words or more, as in
 * `FOLDER NOT EMPTY` or `NO SHEAF.JSON`, so that `HTML` alone never counts.
 */
const TITLE = "[A-Z][A-Z0-9.]*(?: [A-Z0-9.]+)+";

/** Every diagnostic title the code can report: a quoted capitalised string. */
function titlesInCode(): Set<string> {
  const sources = [
    ...filesUnder(join(REPO, "cli/src"), ".ts").filter(
      // The starter's files, embedded as text, are not diagnostics.
      (path) => !path.endsWith("starter.generated.ts"),
    ),
    ...filesUnder(join(REPO, "src"), ".elm"),
  ];
  const quoted = new RegExp(`"(${TITLE})"`, "g");
  return new Set(
    sources.flatMap((path) =>
      [...read(path).matchAll(quoted)].map((match) => match[1] ?? ""),
    ),
  );
}

function titlesInDocs(text: string): Set<string> {
  const backticked = new RegExp(`\`(${TITLE})\``, "g");
  return new Set([...text.matchAll(backticked)].map((match) => match[1] ?? ""));
}

/** `sheaf build`, `bunx sheaf dev`, `bunx elm-sheaf init`, or `…/cli/src/index.ts check` from a clone. */
const COMMAND =
  /(?:\bbunx (?:elm-)?sheaf|(?<![\w./-])sheaf|\bindex\.ts) (build|check|dev|init)\b/g;
const OPTION = /(?<![\w-])--[a-z][a-z-]*/g;

type Use = { command: string; option: string; line: string };

/**
 * Pairs each option with the command it was written for: the closest command
 * before it on the line or, in a code block, on an earlier line of the block;
 * failing that, the first command after it.
 */
function optionUses(lines: string[], acrossLines: boolean): Use[] {
  const uses: Use[] = [];
  let previous: string | undefined;
  const commandsOf = (line: string) =>
    [...line.matchAll(COMMAND)].map((match) => ({
      command: match[1] ?? "",
      index: match.index,
    }));
  const firstInBlock = lines.flatMap(commandsOf)[0]?.command;

  for (const line of lines) {
    const commands = commandsOf(line);
    if (!acrossLines) previous = undefined;
    for (const option of line.matchAll(OPTION)) {
      const before = commands.filter(({ index }) => index < option.index).pop();
      const command =
        before?.command ??
        previous ??
        (acrossLines ? firstInBlock : commands[0]?.command);
      if (command !== undefined)
        uses.push({ command, option: option[0], line });
    }
    previous = commands.at(-1)?.command ?? previous;
  }
  return uses;
}

/** The help is quoted whole, so its options are checked against it separately. */
function isHelp(block: string[]): boolean {
  return block[0] === "Usage: sheaf <command> [options]";
}

/** The options each command's usage line in `sheaf --help` lists. */
function usageOptions(help: string): Map<string, Set<string>> {
  const usage = new Map<string, Set<string>>();
  for (const match of help.matchAll(/^ {2}sheaf ([a-z]+) (.*?) {2,}/gm)) {
    const options = [...(match[2] ?? "").matchAll(OPTION)].map(([o]) => o);
    usage.set(match[1] ?? "", new Set(options));
  }
  return usage;
}

describe("the documentation", () => {
  const userDocs = [join(REPO, "README.md"), ...guidePages()];
  let help = "";

  beforeAll(async () => {
    const child = Bun.spawn([process.execPath, ENTRY, "--help"], {
      stdout: "pipe",
    });
    help = await new Response(child.stdout).text();
  });

  test("has a guide", () => {
    expect(guidePages().map((path) => relative(GUIDE, path))).toEqual([
      "cli.md",
      "configuration.md",
      "content.md",
      "deploying.md",
      "getting-started.md",
      "static-files-and-images.md",
      "templates.md",
    ]);
    const pages = guidePages().map((path) => guidePage(path).data);
    for (const data of pages) {
      expect(typeof data.title).toBe("string");
      expect(Number.isInteger(data.order)).toBe(true);
      expect(typeof data.description).toBe("string");
    }
    const byOrder = pages
      .map((data) => [data.order, data.title])
      .sort(([a], [b]) => Number(a) - Number(b));
    expect(byOrder).toEqual([
      [1, "Getting started"],
      [2, "Content"],
      [3, "Templates"],
      [4, "Configuration"],
      [5, "Static files and images"],
      [6, "Deploying"],
      [7, "CLI reference"],
    ]);
  });

  test("gives no page a title heading", () => {
    const titled = guidePages()
      .filter((path) =>
        splitMarkdown(guidePage(path).body).prose.some((line) =>
          line.startsWith("# "),
        ),
      )
      .map((path) => relative(REPO, path));
    expect(titled).toEqual([]);
  });

  test("links to fragments that exist", () => {
    const idsOf = (path: string) => {
      const sheaf = new HeadingIds();
      const github = new Map<string, number>();
      return splitMarkdown(guidePage(path).body)
        .prose.map((line) => /^#{1,6} +(.+?) *#*$/.exec(line)?.[1])
        .filter((text) => text !== undefined)
        .map((text) => {
          const plain = text.replaceAll("`", "");
          const base = plain
            .toLowerCase()
            .replace(/[^\p{L}\p{N}\p{M} _-]/gu, "")
            .replaceAll(" ", "-");
          const repeats = github.get(base) ?? 0;
          github.set(base, repeats + 1);
          return {
            sheaf: sheaf.next(plain),
            github: repeats === 0 ? base : `${base}-${repeats}`,
          };
        });
    };
    const unequal: string[] = [];
    const missing: string[] = [];
    for (const path of guidePages()) {
      const prose = splitMarkdown(guidePage(path).body)
        .prose.join("\n")
        .replace(/`[^`]*`/g, "");
      for (const match of prose.matchAll(
        /\]\(([^)#\s]*)#([^)\s]+)(?:\s+"[^"]*")?\)/g,
      )) {
        const target = match[1] ? join(dirname(path), match[1]) : path;
        if (!existsSync(target)) continue;
        const heading = idsOf(target).find((ids) => ids.github === match[2]);
        const label = `${relative(REPO, path)}: ${match[1]}#${match[2]}`;
        if (heading === undefined) missing.push(label);
        else if (heading.sheaf !== heading.github) unequal.push(label);
      }
    }
    expect(missing).toEqual([]);
    expect(unequal).toEqual([]);
  });

  test("links out of the guide with absolute URLs", () => {
    const escaping = guidePages().flatMap((path) => {
      const prose = splitMarkdown(guidePage(path).body)
        .prose.join("\n")
        .replace(/`[^`]*`/g, "");
      return [...prose.matchAll(/\]\((\.\.\/[^)\s]*)/g)].map(
        (match) => `${relative(REPO, path)}: ${match[1]}`,
      );
    });
    expect(escaping).toEqual([]);
  });

  test("gives each command only the options its usage line lists", () => {
    const usage = usageOptions(help);
    expect([...usage.keys()].sort()).toEqual(["build", "check", "dev", "init"]);

    const misused = userDocs.flatMap((path) => {
      const { prose, codeBlocks } = splitMarkdown(read(path));
      return [
        ...optionUses(prose, false),
        ...codeBlocks
          .filter((block) => !isHelp(block))
          .flatMap((block) => optionUses(block, true)),
      ]
        .filter(({ command, option }) => !usage.get(command)?.has(option))
        .map(
          ({ command, option, line }) =>
            `${relative(REPO, path)}: ${option} for ${command} in "${line.trim()}"`,
        );
    });
    expect(misused).toEqual([]);
  });

  test("quotes `sheaf --help` as it is", () => {
    const quoted = splitMarkdown(read(join(GUIDE, "cli.md"))).codeBlocks.filter(
      isHelp,
    );
    expect(quoted.map((block) => `${block.join("\n")}\n`)).toEqual([help]);
  });

  test("names only diagnostics the code reports", () => {
    const known = titlesInCode();
    const unknown = guidePages().flatMap((path) =>
      [...titlesInDocs(read(path))]
        .filter((title) => !known.has(title))
        .map((title) => `${relative(REPO, path)}: ${title}`),
    );
    expect(unknown).toEqual([]);
  });

  test("lists every diagnostic in the CLI reference", () => {
    const cliPage = join(GUIDE, "cli.md");
    const documented = existsSync(cliPage)
      ? titlesInDocs(read(cliPage))
      : new Set<string>();
    const missing = [...titlesInCode()]
      .filter((title) => !documented.has(title))
      .sort();
    expect(missing).toEqual([]);
  });

  test("has no broken relative links", () => {
    const linked = [
      join(REPO, "README.md"),
      join(REPO, "CONTRIBUTING.md"),
      ...guidePages(),
    ];
    const broken = linked.flatMap((path) => {
      const prose = splitMarkdown(read(path))
        .prose.join("\n")
        .replace(/`[^`]*`/g, "");
      const targets = [
        ...[...prose.matchAll(/\]\(([^)\s]+)(?:\s+"[^"]*")?\)/g)].map(
          (match) => match[1] ?? "",
        ),
        ...[...prose.matchAll(/^\s*\[[^\]]+\]:\s*(\S+)/gm)].map(
          (match) => match[1] ?? "",
        ),
      ];
      return targets
        .filter((target) => !/^([a-z][a-z0-9+.-]*:|#)/i.test(target))
        .map((target) => target.replace(/#.*$/, ""))
        .filter((target) => !existsSync(join(dirname(path), target)))
        .map((target) => `${relative(REPO, path)}: ${target}`);
    });
    expect(broken).toEqual([]);
  });
});

const RAW = "https://raw.githubusercontent.com/IanRamosC/elm-sheaf/main/";

/**
 * The repository paths of the images a Markdown file shows, written either
 * relative to the file or as a `raw.githubusercontent.com` URL on `main`.
 * Images hosted elsewhere, such as badges, are left out. A reference-style
 * image whose label has no definition is kept as written, so it shows up as
 * missing.
 */
function imagesShownBy(path: string): string[] {
  const prose = splitMarkdown(read(path)).prose.join("\n");
  const definitions = new Map(
    [...prose.matchAll(/^\s*\[([^\]]+)\]:\s*(\S+)/gm)].map((match) => [
      (match[1] ?? "").toLowerCase(),
      match[2] ?? "",
    ]),
  );
  const targets = [
    ...[...prose.matchAll(/!\[[^\]]*\]\(([^)\s]+)/g)].map(
      (match) => match[1] ?? "",
    ),
    ...[...prose.matchAll(/!\[[^\]]*\]\[([^\]]+)\]/g)].map(
      (match) =>
        definitions.get((match[1] ?? "").toLowerCase()) ??
        `${match[0]} (no definition)`,
    ),
  ];
  return targets.flatMap((target) => {
    if (target.startsWith("![")) return [target];
    if (target.startsWith(RAW)) return [target.slice(RAW.length)];
    if (/^[a-z][a-z0-9+.-]*:/i.test(target)) return [];
    return [relative(REPO, join(dirname(path), target))];
  });
}

describe("the repository's images", () => {
  const ASSETS = join(REPO, ".github/assets");
  const IMAGES = [
    join(REPO, "docs/content/guide"),
    join(REPO, "docs/static/images"),
  ];
  const filesIn = (directory: string, extension: string) =>
    existsSync(directory) ? filesUnder(directory, extension) : [];

  test("include every image the README and the guide show", () => {
    const shown = [join(REPO, "README.md"), ...guidePages()].flatMap((path) =>
      imagesShownBy(path).map((image) => ({ page: path, image })),
    );
    expect(shown.map(({ image }) => image)).toContain(
      ".github/assets/logo.svg",
    );
    const missing = shown
      .filter(({ image }) => !existsSync(join(REPO, image)))
      .map(({ page, image }) => `${relative(REPO, page)}: ${image}`);
    expect(missing).toEqual([]);
  });

  test("draw each icon on a 64 by 64 grid, with a title", () => {
    const icons = filesIn(ASSETS, ".svg").filter(
      (path) => !path.endsWith("social-preview.svg"),
    );
    expect(icons.map((path) => relative(ASSETS, path)).sort()).toEqual([
      "favicon.svg",
      "logo-dark.svg",
      "logo.svg",
    ]);
    const malformed = icons
      .filter((path) => {
        const svg = read(path);
        return (
          !svg.includes('viewBox="0 0 64 64"') ||
          !/<title>[^<]+<\/title>/.test(svg)
        );
      })
      .map((path) => relative(REPO, path));
    expect(malformed).toEqual([]);
  });

  test("keep every PNG under 300 KB", () => {
    const pngs = [
      ...filesIn(ASSETS, ".png"),
      ...IMAGES.flatMap((directory) => filesIn(directory, ".png")),
    ];
    expect(pngs.length).toBeGreaterThan(0);
    const large = pngs
      .filter((path) => Bun.file(path).size >= 300 * 1024)
      .map((path) => `${relative(REPO, path)}: ${Bun.file(path).size} bytes`);
    expect(large).toEqual([]);
  });
});

test("the code of conduct names no email address", () => {
  const path = join(REPO, "CODE_OF_CONDUCT.md");
  expect(existsSync(path)).toBe(true);
  const text = existsSync(path) ? read(path) : "";
  expect(text.match(/[\w.+-]+@[\w-]+\.[\w.]+/g) ?? []).toEqual([]);
});

test("no file in the repository refers to internal planning documents", () => {
  const listed = Bun.spawnSync(["git", "ls-files", "-z"], { cwd: REPO });
  expect(listed.exitCode).toBe(0);
  const references = [/\bPlan \d+\b/, /follow-?ups? doc/i];
  const found = listed.stdout
    .toString()
    .split("\0")
    .filter((path) => path !== "")
    .flatMap((path) => {
      const bytes = readFileSync(join(REPO, path));
      // Git's own test for a binary file: a NUL byte near the start.
      if (bytes.subarray(0, 8000).includes(0)) return [];
      return bytes
        .toString("utf8")
        .split("\n")
        .flatMap((line, index) =>
          references.some((reference) => reference.test(line))
            ? [`${path}:${index + 1}: ${line.trim()}`]
            : [],
        );
    });
  expect(found).toEqual([]);
});
