import { describe, expect, test } from "bun:test";
import { planImage, variantWidths } from "../../src/images/plan";

const images = { widths: [480, 960, 1600], formats: ["webp" as const] };

describe("variantWidths", () => {
  test("never upscales a small image", () => {
    expect(variantWidths(300, [480, 960, 1600])).toEqual([300]);
  });

  test("keeps the configured widths below the original, then the original", () => {
    expect(variantWidths(960, [480, 960, 1600])).toEqual([480, 960]);
  });

  test("stops at the largest configured width", () => {
    expect(variantWidths(4000, [480, 960, 1600])).toEqual([480, 960, 1600]);
  });

  test("sorts the configured widths and drops duplicates", () => {
    expect(variantWidths(1000, [960, 480, 480])).toEqual([480, 960]);
  });
});

describe("planImage", () => {
  test("writes the original format first, then WebP, with scaled heights", () => {
    const { local, files } = planImage(
      "0123456789abcdef",
      { format: "png", width: 1200, height: 800 },
      images,
    );

    expect(local).toEqual({
      src: "/_sheaf/images/0123456789abcdef-1200.png",
      width: 1200,
      height: 800,
      variants: [
        {
          mediaType: "image/png",
          files: [
            { path: "/_sheaf/images/0123456789abcdef-480.png", width: 480 },
            { path: "/_sheaf/images/0123456789abcdef-960.png", width: 960 },
            { path: "/_sheaf/images/0123456789abcdef-1200.png", width: 1200 },
          ],
        },
        {
          mediaType: "image/webp",
          files: [
            { path: "/_sheaf/images/0123456789abcdef-480.webp", width: 480 },
            { path: "/_sheaf/images/0123456789abcdef-960.webp", width: 960 },
            { path: "/_sheaf/images/0123456789abcdef-1200.webp", width: 1200 },
          ],
        },
      ],
    });
    expect(files).toHaveLength(6);
    expect(files[0]).toEqual({
      name: "0123456789abcdef-480.png",
      width: 480,
      height: 320,
      format: "png",
    });
  });

  test("rounds heights down, as the encoder does", () => {
    const { files } = planImage(
      "h",
      { format: "png", width: 1201, height: 801 },
      { widths: [1000], formats: [] },
    );
    expect(files).toEqual([
      { name: "h-1000.png", width: 1000, height: 666, format: "png" },
    ]);
  });

  test("writes a WebP source once per width", () => {
    const { local, files } = planImage(
      "h",
      { format: "webp", width: 1000, height: 500 },
      images,
    );
    expect(local.variants.map(({ mediaType }) => mediaType)).toEqual([
      "image/webp",
    ]);
    expect(files.map(({ name }) => name)).toEqual([
      "h-480.webp",
      "h-960.webp",
      "h-1000.webp",
    ]);
  });

  test("names JPEG variants .jpg", () => {
    const { local } = planImage(
      "h",
      { format: "jpeg", width: 400, height: 300 },
      images,
    );
    expect(local.src).toBe("/_sheaf/images/h-400.jpg");
    expect(local.variants[0]?.mediaType).toBe("image/jpeg");
  });

  test("copies GIF and SVG files unchanged, without variants", () => {
    for (const format of ["gif", "svg"] as const) {
      const { local, files } = planImage(
        "h",
        { format, width: 24, height: 12 },
        images,
      );
      expect(local).toEqual({
        src: `/_sheaf/images/h-24.${format}`,
        width: 24,
        height: 12,
        variants: [],
      });
      expect(files).toEqual([
        { name: `h-24.${format}`, width: 24, height: 12, format },
      ]);
    }
  });
});
