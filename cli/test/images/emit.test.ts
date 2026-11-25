import { describe, expect, test } from "bun:test";
import { imageOutputs } from "../../src/images/emit";

describe("imageOutputs", () => {
  test("copies each output path once", () => {
    expect(
      imageOutputs([
        { cached: "/cache/h-480.webp", path: "_sheaf/images/h-480.webp" },
        { cached: "/cache/h-480.webp", path: "_sheaf/images/h-480.webp" },
        { cached: "/cache/h-480.png", path: "_sheaf/images/h-480.png" },
      ]),
    ).toEqual([
      {
        kind: "copy",
        path: "_sheaf/images/h-480.webp",
        source: "/cache/h-480.webp",
      },
      {
        kind: "copy",
        path: "_sheaf/images/h-480.png",
        source: "/cache/h-480.png",
      },
    ]);
  });
});
