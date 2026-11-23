import { readdir, readFile } from "node:fs/promises";
import { join, relative, sep } from "node:path";
import type { Config } from "../config/config";
import type { Diagnostic } from "../diagnostics/diagnostic";
import { elmModuleName } from "../elm/names";
import { err, ok, type Result } from "../result";
import { URL_SCHEMES } from "../url-schemes";
import { type DocumentDate, publicationDate } from "./dates";
import type { SourceDocument } from "./document";
import { splitFrontmatter } from "./frontmatter";

/** A Markdown file and its text; `path` is relative to the site root. */
export type ContentFile = { path: string; source: string };

/** `drafts` also builds drafts and documents dated in the future. */
export type BuildMode = "production" | "drafts";

const RESERVED_KEYS = ["slug", "date", "updated", "draft", "image"];
const COLLECTION_NAME = /^[a-z][a-z0-9-]*$/;
const DATED_NAME = /^(\d{4}-\d{2}-\d{2})-(.+)$/;
const DOCUMENT_FOLDER_INDEX = "index.md";

/**
 * A site without a `content/` folder has no content. That is not an error
 * here: a template that asks for a collection gets Elm's own explanation.
 */
async function readContentEntries(root: string, recursive: boolean) {
  try {
    return await readdir(join(root, "content"), {
      recursive,
      withFileTypes: true,
    });
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return [];
    throw error;
  }
}

const isHidden = (name: string) => name.startsWith(".");

/**
 * The name of every folder in `<root>/content`, empty ones included, sorted.
 * Hidden folders (`.obsidian`, `.git`) belong to other tools, so they are skipped.
 */
export async function readCollectionNames(root: string): Promise<string[]> {
  const entries = await readContentEntries(root, false);
  return entries
    .filter((entry) => entry.isDirectory() && !isHidden(entry.name))
    .map((entry) => entry.name)
    .sort();
}

/**
 * Reads every `.md` file under `<root>/content`, sorted by path so builds are
 * repeatable, with paths relative to `root` and `/` separators on every OS.
 */
export async function readContentFiles(root: string): Promise<ContentFile[]> {
  const entries = await readContentEntries(root, true);
  const paths = entries
    .filter((entry) => entry.isFile() && entry.name.endsWith(".md"))
    .map((entry) =>
      relative(root, join(entry.parentPath, entry.name)).split(sep).join("/"),
    )
    .filter((path) => !path.split("/").some(isHidden))
    .sort();
  return Promise.all(
    paths.map(async (path) => ({
      path,
      source: await readFile(join(root, path), "utf8"),
    })),
  );
}

/**
 * Turns content files into documents, reporting every problem found across
 * all of them. It is pure: the caller reads the disk. `collections` lists
 * every folder of `content/`, so an empty one is checked too; it defaults to
 * the folders the files are in.
 */
export function loadContent(
  files: ContentFile[],
  config: Config,
  buildStart: Date,
  mode: BuildMode,
  collections: string[] = foldersOf(files),
): Result<SourceDocument[], Diagnostic[]> {
  const documents: SourceDocument[] = [];
  const problems = [
    ...collectionNameProblems(collections),
    ...moduleClashProblems(collections),
  ];

  for (const file of files) {
    const loaded = loadDocument(file, config, buildStart, mode);
    if (loaded.ok) {
      documents.push(loaded.value);
    } else {
      problems.push(...loaded.error);
    }
  }
  problems.push(...collisionProblems(documents));

  return problems.length > 0 ? err(problems) : ok(documents);
}

type Layout = { collection: string; name: string };

function loadDocument(
  file: ContentFile,
  config: Config,
  buildStart: Date,
  mode: BuildMode,
): Result<SourceDocument, Diagnostic[]> {
  const { path } = file;
  const layout = parseLayout(path);
  if (!layout.ok) return err([layout.error]);
  const { collection, name } = layout.value;

  const split = splitFrontmatter(file.source, path);
  if (!split.ok) return split;
  const { data, positions } = split.value;

  const problems: Diagnostic[] = [];
  const fileProblem = (title: string, message: string): Diagnostic => ({
    severity: "error",
    title,
    message,
    sourcePath: path,
  });
  // Reserved-key errors underline the key, so the author sees which field
  // the host was reading.
  const readKey = <T>(
    key: string,
    parse: (value: unknown) => Result<T, string>,
  ): T | undefined => {
    if (!(key in data)) return undefined;
    const parsed = parse(data[key]);
    if (parsed.ok) return parsed.value;
    problems.push({
      severity: "error",
      title: "BAD FRONTMATTER",
      message: `The \`${key}\` field is not valid. ${parsed.error}`,
      sourcePath: path,
      ...(positions[key]?.key && { span: positions[key].key }),
    });
    return undefined;
  };

  const dated = DATED_NAME.exec(name);
  const filenameSlug = dated?.[2] ?? name;

  const slugOverride = readKey("slug", parseSlug);
  if (slugOverride === undefined && !isSlug(filenameSlug)) {
    problems.push(
      fileProblem(
        "BAD SLUG",
        `The name \`${filenameSlug}\` cannot become a URL. ${SLUG_RULE} Rename it, or set \`slug:\` in the frontmatter.`,
      ),
    );
  }
  const slug = slugOverride ?? filenameSlug;

  const asDate = (value: unknown): Result<DocumentDate, string> =>
    typeof value === "string"
      ? publicationDate(value, config.timezone)
      : err("Write it as YYYY-MM-DD.");
  const filenameDate = dated && asDate(dated[1]);
  if (filenameDate && !filenameDate.ok) {
    problems.push(
      fileProblem(
        "BAD DATE",
        `The date in this file name is not valid. ${filenameDate.error}`,
      ),
    );
  }
  const date =
    readKey("date", asDate) ??
    (filenameDate?.ok ? filenameDate.value : undefined);
  const updated = readKey("updated", asDate);
  const draft = readKey("draft", parseDraft) ?? false;
  const imageSource = readKey("image", parseImage);

  if (problems.length > 0) return err(problems);

  const excluded =
    mode === "production" &&
    (draft || (date !== undefined && date.instant > buildStart));

  return ok({
    id: `${collection}/${slug}`,
    collection,
    sourcePath: path,
    slug,
    ...(date && { date }),
    ...(updated && { updated }),
    draft,
    excluded,
    ...(imageSource !== undefined && { imageSource }),
    frontmatter: withoutReservedKeys(data),
    frontmatterPositions: positions,
    body: split.value.body,
    bodyStartLine: split.value.bodyStartLine,
  });
}

/** Finds the collection and document name in `content/<collection>/<name>.md` or `…/<name>/index.md`. */
function parseLayout(path: string): Result<Layout, Diagnostic> {
  const [, ...inside] = path.split("/");
  const misplaced = (message: string): Diagnostic => ({
    severity: "error",
    title: "MISPLACED DOCUMENT",
    message,
    sourcePath: path,
  });

  const [collection, second, third, ...deeper] = inside;
  if (collection === undefined || second === undefined) {
    return err(
      misplaced(
        "Documents live in a collection folder, such as content/posts/, not directly in content/.",
      ),
    );
  }
  if (third === undefined) {
    return ok({ collection, name: second.replace(/\.md$/, "") });
  }
  if (third === DOCUMENT_FOLDER_INDEX && deeper.length === 0) {
    return ok({ collection, name: second });
  }
  return err(
    misplaced(
      "A document is either `<name>.md` or `<name>/index.md` inside a collection folder.",
    ),
  );
}

function foldersOf(files: ContentFile[]): string[] {
  const folders = new Set(
    files.flatMap(({ path }) => {
      const [, folder, ...rest] = path.split("/");
      // A file directly in content/ has no collection; it is reported as misplaced.
      return folder !== undefined && rest.length > 0 ? [folder] : [];
    }),
  );
  return [...folders];
}

function collectionNameProblems(collections: string[]): Diagnostic[] {
  return collections.flatMap((name) => {
    const message = collectionNameMessage(name);
    return message === undefined
      ? []
      : [
          {
            severity: "error" as const,
            title: "BAD COLLECTION NAME",
            message,
            sourcePath: `content/${name}`,
          },
        ];
  });
}

/**
 * Each collection becomes an Elm module, and names such as `a-b` and `a--b`
 * both become `Content.AB`, so one module would silently replace the other.
 */
function moduleClashProblems(collections: string[]): Diagnostic[] {
  const foldersByModule = new Map<string, string[]>();
  for (const name of collections) {
    if (collectionNameMessage(name) !== undefined) continue;
    const moduleName = elmModuleName(name);
    if (!moduleName.ok) continue;
    const folders = foldersByModule.get(moduleName.value) ?? [];
    foldersByModule.set(moduleName.value, [...folders, `content/${name}`]);
  }
  return [...foldersByModule].flatMap(([moduleName, folders]) => {
    const [first, ...others] = folders;
    if (first === undefined || others.length === 0) return [];
    return [
      {
        severity: "error",
        title: "NAME CLASH",
        message: `The folders ${folders.join(", ")} all become the Elm module \`Content.${moduleName}\`.`,
        sourcePath: first,
        hint: "Rename all but one of these folders.",
      },
    ];
  });
}

function collectionNameMessage(name: string): string | undefined {
  if (!COLLECTION_NAME.test(name)) {
    return `The folder name \`${name}\` cannot be a collection. Collection names use lowercase letters, digits and hyphens, and start with a letter.`;
  }
  if (URL_SCHEMES.includes(name)) {
    return `\`${name}\` is a URL scheme, so \`${name}:something\` in a link could not be told apart from a link to a ${name} URL. Choose another collection name.`;
  }
  return undefined;
}

/** Reports documents that would share a URL, naming every file involved. */
function collisionProblems(documents: SourceDocument[]): Diagnostic[] {
  const pathsById = new Map<string, string[]>();
  for (const { id, sourcePath } of documents) {
    pathsById.set(id, [...(pathsById.get(id) ?? []), sourcePath]);
  }
  return [...pathsById].flatMap(([id, paths]) => {
    const [first, ...others] = paths;
    if (first === undefined || others.length === 0) return [];
    return [
      {
        severity: "error",
        title: "DUPLICATE DOCUMENT",
        message: `These files all become \`${id}\`: ${paths.join(", ")}.`,
        sourcePath: first,
        hint: "Rename one of them, or give it a different `slug:`.",
      },
    ];
  });
}

const SLUG_RULE =
  "A slug is a single path segment without `/`, `\\`, spaces or control characters, and without `#`, `?` or `%`, which would end or escape the URL path.";

function isSlug(text: string): boolean {
  return text !== "." && text !== ".." && /^[^/\\\s\p{Cc}#?%]+$/u.test(text);
}

function parseSlug(value: unknown): Result<string, string> {
  if (typeof value !== "string") return err("It must be text.");
  return isSlug(value) ? ok(value) : err(SLUG_RULE);
}

function parseDraft(value: unknown): Result<boolean, string> {
  return typeof value === "boolean"
    ? ok(value)
    : err("It must be true or false.");
}

function parseImage(value: unknown): Result<string, string> {
  return typeof value === "string" ? ok(value) : err("It must be a file name.");
}

function withoutReservedKeys(
  data: Record<string, unknown>,
): Record<string, unknown> {
  return Object.fromEntries(
    Object.entries(data).filter(([key]) => !RESERVED_KEYS.includes(key)),
  );
}
