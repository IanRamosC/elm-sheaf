import { constants } from "node:fs";
import {
  access,
  mkdir,
  readdir,
  readFile,
  realpath,
  rename,
  rm,
  writeFile,
} from "node:fs/promises";
import { join, posix, sep } from "node:path";
import type { Config } from "../config/config";
import type { SourceDocument } from "../content/document";
import { type ContentFiles, isErrno } from "../content/files";
import type { Diagnostic, Span } from "../diagnostics/diagnostic";
import type { DocumentImage } from "../elm/protocol";
import type { LocalImage, Node } from "../markdown/tree";
import { err, ok, type Result } from "../result";
import { suggestions } from "../suggest";
import {
  type CodecFailure,
  checkDecodes,
  encodeVariant,
  imageHash,
  readRasterInfo,
} from "./codec";
import {
  IMAGE_FOLDER,
  type ImageInfo,
  type PlannedFile,
  planImage,
} from "./plan";
import { slotLimiter } from "./slots";
import { isSvg, svgSize } from "./svg";

/** A cached image file and the path, relative to `dist/`, it is published at. */
export type ImageFile = { cached: string; path: string };

type Image = Extract<Node, { type: "image" }>;

/** A problem with an image, before it is located at the reference. */
type Problem = { title: string; message: string; hint?: string };

type Published = { local: LocalImage; files: ImageFile[] };

const CACHE_FOLDER = ".sheaf/cache/images";
const PASSES_THROUGH = /^(?:https?:|data:|\/\/)/i;
const REMOTE_COVER = /^https?:/i;
const SCHEME = /^[A-Za-z][A-Za-z0-9+.-]*:/;
const PUBLISHED_FORMATS = "JPEG, PNG, WebP, GIF or SVG";

/**
 * Finds every local image of a document, in its body and its `image` key,
 * and gives each its published files. Images whose variants are not all in
 * `.sheaf/cache/images/` are decoded and encoded now, in `check` as in
 * `build`, so a damaged file is reported where it is used. Every problem is
 * reported, not just the first.
 */
export async function resolveImages(
  tree: Node,
  document: SourceDocument,
  siteRoot: string,
  config: Config,
  files: ContentFiles,
): Promise<
  Result<
    { tree: Node; image?: DocumentImage; files: ImageFile[] },
    Diagnostic[]
  >
> {
  const published = new Map<string, Promise<Result<Published, Problem>>>();
  const publish = async (url: string) => {
    const found = await locateImage(url, document.sourcePath, siteRoot, files);
    if (!found.ok) return found;
    let pending = published.get(found.value);
    if (pending === undefined) {
      pending = publishImage(siteRoot, found.value, config.images);
      published.set(found.value, pending);
    }
    return pending;
  };

  const images = imagesIn(tree).filter(({ url }) => !PASSES_THROUGH.test(url));
  const cover = document.image;
  const localCover =
    cover !== undefined && !REMOTE_COVER.test(cover.src) ? cover : undefined;
  const [coverResult, ...imageResults] = await Promise.all([
    localCover && publish(localCover.src),
    ...images.map(({ url }) => publish(url)),
  ]);

  const diagnostics: Diagnostic[] = [];
  const imageFiles: ImageFile[] = [];
  const report = (problem: Problem, span: Span | undefined) =>
    diagnostics.push({
      severity: "error",
      ...problem,
      sourcePath: document.sourcePath,
      ...(span && { span }),
    });

  let image: DocumentImage | undefined;
  if (cover !== undefined) image = { url: cover.src, alt: cover.alt };
  if (image !== undefined && coverResult !== undefined) {
    if (coverResult.ok) {
      image.local = coverResult.value.local;
      imageFiles.push(...coverResult.value.files);
    } else {
      const imageKey = document.frontmatterPositions.find(
        ({ path }) => path === "image",
      )?.key;
      report(coverResult.error, imageKey);
    }
  }

  const locals = new Map<Image, LocalImage>();
  images.forEach((node, index) => {
    const result = imageResults[index];
    if (result === undefined) return;
    if (result.ok) {
      locals.set(node, result.value.local);
      imageFiles.push(...result.value.files);
    } else {
      report(result.error, node.position);
    }
  });

  if (diagnostics.length > 0) return err(diagnostics);
  return ok({
    tree: withLocalImages(tree, locals),
    ...(image && { image }),
    files: imageFiles,
  });
}

function imagesIn(node: Node): Image[] {
  if (node.type === "image") return [node];
  return "children" in node ? node.children.flatMap(imagesIn) : [];
}

function withLocalImages(node: Node, locals: Map<Image, LocalImage>): Node {
  if (node.type === "image") {
    const local = locals.get(node);
    return local === undefined ? node : { ...node, local };
  }
  if (!("children" in node)) return node;
  return {
    ...node,
    children: node.children.map((child) => withLocalImages(child, locals)),
  };
}

/**
 * The site path of the file an image refers to: relative to the document and
 * inside `content/`, or from `static/` when it starts with `/`. Both are
 * checked by path and again after following symlinks.
 */
async function locateImage(
  url: string,
  sourcePath: string,
  siteRoot: string,
  files: ContentFiles,
): Promise<Result<string, Problem>> {
  if (SCHEME.test(url)) {
    return err({
      title: "UNSUPPORTED IMAGE",
      message: `The image \`${url}\` is neither a file of this site nor an http or https URL.`,
      hint: "Use a path such as `photo.png`, a path into `static/` such as `/logo.png`, or a full https URL.",
    });
  }
  const path = decode(url);
  if (path === undefined) {
    return err({
      title: "MISSING IMAGE",
      message: `The image \`${url}\` is not validly percent-encoded, so I cannot tell which file it means.`,
    });
  }
  const [folder, base] = path.startsWith("/")
    ? ["static", "static"]
    : ["content", posix.dirname(sourcePath)];
  const outside: Problem = {
    title: "IMAGE OUTSIDE FOLDER",
    message: `The image \`${path}\` is outside \`${folder}/\`. ${
      folder === "static"
        ? "An image path starting with `/` is read from `static/`."
        : "A relative image path is read from this document's folder, and must stay inside `content/`."
    }`,
    hint: "Move the image into `content/` next to this document, or into `static/` and refer to it with a path starting with `/`.",
  };
  const target = posix.join(base, path);
  if (!target.startsWith(`${folder}/`)) return err(outside);

  const lookup = files.find(target);
  if (lookup === undefined) {
    const [closest] = suggestions(
      posix.basename(target),
      files.namesIn(posix.dirname(target)),
      1,
    );
    return err({
      title: "MISSING IMAGE",
      message: `There is no image at \`${path}\`. I looked for \`${target}\`.`,
      ...(closest !== undefined && { hint: `Did you mean \`${closest}\`?` }),
    });
  }
  if ("caseOf" in lookup) {
    return err({
      title: "CASE MISMATCH",
      message: `The file is \`${posix.relative(base, lookup.caseOf)}\`, but this refers to \`${posix.relative(base, target)}\`. Linux treats them as different files, so the site would fail to build there.`,
    });
  }
  try {
    const [real, realFolder] = await Promise.all([
      realpath(join(siteRoot, lookup.found)),
      realpath(join(siteRoot, folder)),
    ]);
    return real.startsWith(realFolder + sep) ? ok(lookup.found) : err(outside);
  } catch (error) {
    // Bun resolves a link by opening the file, so some systems fail here
    // for a file that cannot be read.
    if (!isErrno(error)) throw error;
    return err(notReadable(lookup.found, error));
  }
}

// Each image holds its source bytes from the read until its variants are
// written, so this bounds how many files are in memory at once. Without it
// every image of the site is read before the first one is encoded.
const withReadSlot = slotLimiter(navigator.hardwareConcurrency);

/** Reads an image, plans its files, and writes those not yet in the cache. */
function publishImage(
  siteRoot: string,
  sitePath: string,
  images: Config["images"],
): Promise<Result<Published, Problem>> {
  return withReadSlot(() => readAndPublish(siteRoot, sitePath, images));
}

async function readAndPublish(
  siteRoot: string,
  sitePath: string,
  images: Config["images"],
): Promise<Result<Published, Problem>> {
  let bytes: Uint8Array;
  try {
    bytes = new Uint8Array(await readFile(join(siteRoot, sitePath)));
  } catch (error) {
    if (!isErrno(error)) throw error;
    return err(notReadable(sitePath, error));
  }
  const info = await readImageInfo(bytes, sitePath);
  if (!info.ok) return info;
  const { local, files } = planImage(imageHash(bytes), info.value, images);
  const cache = join(siteRoot, CACHE_FOLDER);

  const cached = await Promise.all(
    files.map((file) => isReadable(join(cache, file.name))),
  );
  const missing = files.filter((_, index) => !cached[index]);
  if (missing.length > 0) {
    try {
      const written = await writeToCache(bytes, missing, cache);
      if (!written.ok) return err(codecProblem(written.error, sitePath));
    } catch (error) {
      if (!isErrno(error)) throw error;
      return err({
        title: "CACHE NOT WRITABLE",
        message: `I could not write to \`${CACHE_FOLDER}/\` (${error.code}), where the encoded images are kept.`,
        hint: `Make sure \`${CACHE_FOLDER}\` is a folder you can write to. It is safe to delete: the next build fills it again.`,
      });
    }
  }
  return ok({
    local,
    files: files.map(({ name }) => ({
      cached: join(cache, name),
      path: `${IMAGE_FOLDER}/${name}`,
    })),
  });
}

function notReadable(sitePath: string, error: NodeJS.ErrnoException): Problem {
  return {
    title: "IMAGE NOT READABLE",
    message: `I could not read \`${sitePath}\` (${error.code}).`,
    hint: "Check that the file can be read by the user running Sheaf.",
  };
}

/**
 * Deletes the files of `.sheaf/cache/images/` that no image of the site uses
 * any more, so the cache does not outgrow the site. `used` must hold the
 * files of every document, drafts included: a production build that dropped a
 * draft's variants would only make the next `--drafts` build encode them again.
 */
export async function pruneImageCache(
  siteRoot: string,
  used: ImageFile[],
): Promise<void> {
  const cache = join(siteRoot, CACHE_FOLDER);
  const keep = new Set(used.map(({ cached }) => cached));
  let names: string[];
  try {
    names = await readdir(cache);
  } catch (error) {
    if (isErrno(error) && error.code === "ENOENT") return;
    throw error;
  }
  await Promise.all(
    names
      .filter((name) => !keep.has(join(cache, name)))
      // A file that cannot be deleted only costs disk space, not a build.
      .map((name) => rm(join(cache, name), { force: true }).catch(() => {})),
  );
}

async function readImageInfo(
  bytes: Uint8Array,
  sitePath: string,
): Promise<Result<ImageInfo, Problem>> {
  const raster = await readRasterInfo(bytes);
  if (raster.ok) {
    const { format, width, height } = raster.value;
    if (
      format === "jpeg" ||
      format === "png" ||
      format === "webp" ||
      format === "gif"
    ) {
      return ok({ format, width, height });
    }
    return err({
      title: "UNSUPPORTED IMAGE",
      message: `\`${sitePath}\` is a ${format.toUpperCase()} image, which not every browser can show.`,
      hint: `Convert it to ${PUBLISHED_FORMATS}, the formats Sheaf publishes.`,
    });
  }
  if (raster.error === "unknown format") {
    const text = new TextDecoder().decode(bytes);
    if (isSvg(text)) {
      const size = svgSize(text);
      if (size !== undefined) return ok({ format: "svg", ...size });
      return err({
        title: "SVG WITHOUT SIZE",
        message: `\`${sitePath}\` has no \`width\` and \`height\` in pixels and no \`viewBox\`, so I cannot tell how much room it takes on the page.`,
        hint: 'Add a viewBox to its <svg> element, such as viewBox="0 0 24 24" for a 24×24 icon.',
      });
    }
  }
  return err(codecProblem(raster.error, sitePath));
}

function codecProblem(failure: CodecFailure, sitePath: string): Problem {
  switch (failure) {
    case "unknown format":
      return {
        title: "BAD IMAGE",
        message: `\`${sitePath}\` is not an image I can read.`,
        hint: `Sheaf publishes ${PUBLISHED_FORMATS} images.`,
      };
    case "damaged":
      return {
        title: "BAD IMAGE",
        message: `I could not decode \`${sitePath}\`: the file is damaged or incomplete.`,
        hint: "Export it again from the program that made it.",
      };
    case "too large":
      return {
        title: "BAD IMAGE",
        message: `\`${sitePath}\` has more pixels than I can decode.`,
        hint: "Scale it down before adding it to the site.",
      };
  }
}

// Two documents may use one image at the same time; they share its writes.
const writing = new Map<string, Promise<Result<void, CodecFailure>>>();

async function writeToCache(
  bytes: Uint8Array,
  files: PlannedFile[],
  cache: string,
): Promise<Result<void, CodecFailure>> {
  // Copied files are never encoded, so a damaged GIF is caught here instead.
  if (files.some(({ format }) => format === "gif")) {
    const decoded = await checkDecodes(bytes);
    if (!decoded.ok) return decoded;
  }
  await mkdir(cache, { recursive: true });
  const results = await Promise.all(
    files.map((file) => {
      const path = join(cache, file.name);
      let pending = writing.get(path);
      if (pending === undefined) {
        pending = writeCacheFile(bytes, file, path).finally(() =>
          writing.delete(path),
        );
        writing.set(path, pending);
      }
      return pending;
    }),
  );
  return results.find((result) => !result.ok) ?? ok(undefined);
}

async function writeCacheFile(
  bytes: Uint8Array,
  { format, width }: PlannedFile,
  path: string,
): Promise<Result<void, CodecFailure>> {
  let content = bytes;
  if (format !== "gif" && format !== "svg") {
    const encoded = await encodeVariant(bytes, width, format);
    if (!encoded.ok) return encoded;
    content = encoded.value;
  }
  // Renamed into place, so an interrupted build never leaves part of a file
  // under the name a later build would trust.
  const temporary = `${path}.${crypto.randomUUID()}.tmp`;
  try {
    await writeFile(temporary, content);
    await rename(temporary, path);
  } finally {
    await rm(temporary, { force: true });
  }
  return ok(undefined);
}

async function isReadable(path: string): Promise<boolean> {
  try {
    await access(path, constants.R_OK);
    return true;
  } catch {
    return false;
  }
}

function decode(text: string): string | undefined {
  try {
    return decodeURIComponent(text);
  } catch {
    return undefined;
  }
}
