import { crc32, deflateSync } from "node:zlib";

/**
 * A real PNG of the given size, with a gradient so that encoders have
 * something to compress. Written by hand rather than with `Bun.Image`,
 * which only encodes images it has decoded first.
 */
export function pngBytes(width: number, height: number): Uint8Array {
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0);
  header.writeUInt32BE(height, 4);
  header[8] = 8; // bits per channel
  header[9] = 2; // truecolour
  const rowLength = width * 3 + 1;
  const pixels = Buffer.alloc(rowLength * height);
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const offset = y * rowLength + 1 + x * 3;
      pixels[offset] = x % 256;
      pixels[offset + 1] = y % 256;
      pixels[offset + 2] = (x + y) % 256;
    }
  }
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", header),
    chunk("IDAT", deflateSync(pixels)),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

function chunk(type: string, data: Buffer): Buffer {
  const out = Buffer.alloc(12 + data.length);
  out.writeUInt32BE(data.length, 0);
  out.write(type, 4, "ascii");
  data.copy(out, 8);
  out.writeUInt32BE(crc32(out.subarray(4, 8 + data.length)), 8 + data.length);
  return out;
}

export function jpegBytes(width: number, height: number): Promise<Uint8Array> {
  return new Bun.Image(pngBytes(width, height)).jpeg().bytes();
}

export function webpBytes(width: number, height: number): Promise<Uint8Array> {
  return new Bun.Image(pngBytes(width, height)).webp().bytes();
}

/** The well-known 1×1 transparent GIF. */
export function gifBytes(): Uint8Array {
  return Buffer.from(
    "R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==",
    "base64",
  );
}

/** A 2×2 24-bit BMP, which `Bun.Image` reads but Sheaf does not publish. */
export function bmpBytes(): Uint8Array {
  const pixelBytes = 8 * 2;
  const bmp = Buffer.alloc(54 + pixelBytes);
  bmp.write("BM", 0, "ascii");
  bmp.writeUInt32LE(bmp.length, 2);
  bmp.writeUInt32LE(54, 10);
  bmp.writeUInt32LE(40, 14);
  bmp.writeInt32LE(2, 18);
  bmp.writeInt32LE(2, 22);
  bmp.writeUInt16LE(1, 26);
  bmp.writeUInt16LE(24, 28);
  bmp.writeUInt32LE(pixelBytes, 34);
  return bmp;
}
