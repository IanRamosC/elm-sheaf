import { createHash } from "node:crypto";
import { err, ok, type Result } from "../result";

// The macOS default backend resizes with Accelerate, which gives different
// bytes than Linux; "bun" gives the same output on every machine.
Bun.Image.backend = "bun";

const QUALITY = 80;

/**
 * Part of every image's hash, so that changing them renames every variant.
 * The Bun version is in it because a Bun upgrade may change the encoders'
 * bytes: without it a warm cache would keep the old bytes while a fresh
 * machine wrote new ones under the same name. The highlight cache keys on
 * Shiki's version for the same reason. Once Sheaf ships as a compiled binary
 * (Plan 5), its own version belongs here too.
 */
const ENCODER_SETTINGS = `bun ${Bun.version}, webp quality ${QUALITY}, jpeg quality ${QUALITY}, png default`;

/** A format Sheaf can encode a variant in. */
export type EncodedFormat = "jpeg" | "png" | "webp";

/** Why `Bun.Image` could not read an image. */
export type CodecFailure = "unknown format" | "damaged" | "too large";

/** The size and format in an image's header, which a damaged file may still have intact. */
export type RasterInfo = {
  format: Bun.Image.Format;
  width: number;
  height: number;
};

/** The first 16 hex digits of SHA-256 over the source bytes, the encoder settings and the encoder version. */
export function imageHash(bytes: Uint8Array): string {
  return createHash("sha256")
    .update(bytes)
    .update(ENCODER_SETTINGS)
    .digest("hex")
    .slice(0, 16);
}

/** Reads only the header, so a truncated file passes; encoding is what catches it. */
export function readRasterInfo(
  bytes: Uint8Array,
): Promise<Result<RasterInfo, CodecFailure>> {
  return attempt(() => new Bun.Image(bytes).metadata());
}

/** Decodes the whole image, for files that are published without encoding. */
export async function checkDecodes(
  bytes: Uint8Array,
): Promise<Result<void, CodecFailure>> {
  const decoded = await withSlot(() =>
    attempt(() => new Bun.Image(bytes).png().bytes()),
  );
  return decoded.ok ? ok(undefined) : decoded;
}

/** Resizes to `width`, keeping the aspect ratio and never enlarging, and encodes. */
export function encodeVariant(
  bytes: Uint8Array,
  width: number,
  format: EncodedFormat,
): Promise<Result<Uint8Array, CodecFailure>> {
  const image = new Bun.Image(bytes).resize(width, undefined, {
    withoutEnlargement: true,
  });
  const encoder =
    format === "png"
      ? image.png()
      : format === "jpeg"
        ? image.jpeg({ quality: QUALITY })
        : image.webp({ quality: QUALITY });
  return withSlot(() => attempt(() => encoder.bytes()));
}

const FAILURES: Partial<Record<Bun.Image.ErrorCode, CodecFailure>> = {
  ERR_IMAGE_UNKNOWN_FORMAT: "unknown format",
  ERR_IMAGE_DECODE_FAILED: "damaged",
  ERR_IMAGE_TOO_MANY_PIXELS: "too large",
};

async function attempt<T>(
  run: () => Promise<T>,
): Promise<Result<T, CodecFailure>> {
  try {
    return ok(await run());
  } catch (error) {
    const failure = failureOf(error);
    if (failure === undefined) throw error;
    return err(failure);
  }
}

function failureOf(error: unknown): CodecFailure | undefined {
  if (!(error instanceof Error) || !("code" in error)) return undefined;
  const { code } = error;
  return Object.entries(FAILURES).find(([known]) => known === code)?.[1];
}

// Each pipeline runs on a worker thread, so more at once than there are cores
// only holds more decoded images in memory.
const SLOTS = navigator.hardwareConcurrency;
let busy = 0;
const waiting: (() => void)[] = [];

async function withSlot<T>(work: () => Promise<T>): Promise<T> {
  if (busy < SLOTS) {
    busy++;
  } else {
    // A finishing task hands its slot straight to the next one waiting.
    await new Promise<void>((resolve) => waiting.push(resolve));
  }
  try {
    return await work();
  } finally {
    const next = waiting.shift();
    if (next === undefined) busy--;
    else next();
  }
}
