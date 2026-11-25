import type { Config } from "../config/config";
import type { LocalImage } from "../markdown/tree";

/** The formats Sheaf publishes; any other image is `UNSUPPORTED IMAGE`. */
export type SourceFormat = "jpeg" | "png" | "webp" | "gif" | "svg";

/** What a source file holds, read from its bytes rather than its name. */
export type ImageInfo = { format: SourceFormat; width: number; height: number };

/**
 * A file to write to the image cache: `name` is also its name under
 * `/_sheaf/images/`. GIF and SVG files are the source copied unchanged.
 */
export type PlannedFile = {
  name: string;
  width: number;
  height: number;
  format: SourceFormat;
};

/** Where images are published, relative to `dist/`. */
export const IMAGE_FOLDER = "_sheaf/images";

const EXTENSIONS: Record<SourceFormat, string> = {
  jpeg: "jpg",
  png: "png",
  webp: "webp",
  gif: "gif",
  svg: "svg",
};

const MEDIA_TYPES: Record<SourceFormat, string> = {
  jpeg: "image/jpeg",
  png: "image/png",
  webp: "image/webp",
  gif: "image/gif",
  svg: "image/svg+xml",
};

/**
 * The widths an image is written at: every configured width below the
 * original, then the original capped at the largest configured width, so
 * nothing is upscaled or larger than the site asks for.
 */
export function variantWidths(
  original: number,
  configured: number[],
): number[] {
  const largest = Math.min(original, Math.max(...configured));
  const widths = new Set([
    ...configured.filter((width) => width < largest),
    largest,
  ]);
  return [...widths].sort((a, b) => a - b);
}

/**
 * Every file an image is published as, and how the page refers to them.
 * `hash` identifies the source bytes and encoder settings, so identical files
 * share their outputs.
 */
export function planImage(
  hash: string,
  info: ImageInfo,
  images: Config["images"],
): { local: LocalImage; files: PlannedFile[] } {
  const fileAt = (width: number, format: SourceFormat): PlannedFile => ({
    name: `${hash}-${width}.${EXTENSIONS[format]}`,
    width,
    // The encoder rounds a scaled height down, so the markup has to as well.
    height: Math.floor((info.height * width) / info.width),
    format,
  });
  const sitePath = (file: PlannedFile) => `/${IMAGE_FOLDER}/${file.name}`;

  if (info.format === "gif" || info.format === "svg") {
    const file = fileAt(info.width, info.format);
    return {
      local: {
        src: sitePath(file),
        width: info.width,
        height: info.height,
        variants: [],
      },
      files: [file],
    };
  }

  const widths = variantWidths(info.width, images.widths);
  const formats = [
    info.format,
    ...images.formats.filter((format) => format !== info.format),
  ];
  const byFormat = formats.map((format) => ({
    format,
    files: widths.map((width) => fileAt(width, format)),
  }));
  const fallback = byFormat[0]?.files.at(-1);
  if (fallback === undefined) throw new Error("An image has no widths");
  return {
    local: {
      src: sitePath(fallback),
      width: fallback.width,
      height: fallback.height,
      variants: byFormat.map(({ format, files }) => ({
        mediaType: MEDIA_TYPES[format],
        files: files.map((file) => ({
          path: sitePath(file),
          width: file.width,
        })),
      })),
    },
    files: byFormat.flatMap(({ files }) => files),
  };
}
