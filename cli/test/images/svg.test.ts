import { describe, expect, test } from "bun:test";
import { isSvg, svgSize } from "../../src/images/svg";

describe("svgSize", () => {
  test("reads unitless and pixel width and height", () => {
    expect(svgSize('<svg width="24" height="12px"></svg>')).toEqual({
      width: 24,
      height: 12,
    });
  });

  test("falls back to the viewBox", () => {
    expect(
      svgSize('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 12"/>'),
    ).toEqual({ width: 24, height: 12 });
  });

  test("uses the viewBox when the width is relative", () => {
    expect(
      svgSize("<svg width='100%' height='50%' viewBox='0,0,30,10'></svg>"),
    ).toEqual({ width: 30, height: 10 });
  });

  test("has no size without width and height or a viewBox", () => {
    expect(svgSize("<svg><path/></svg>")).toBeUndefined();
  });
});

describe("isSvg", () => {
  test("accepts an SVG after an XML declaration and a comment", () => {
    expect(isSvg('﻿<?xml version="1.0"?>\n<!-- logo -->\n<svg></svg>')).toBe(
      true,
    );
  });

  test("rejects other text", () => {
    expect(isSvg("hello <svg>")).toBe(false);
    expect(isSvg("<html><svg></svg></html>")).toBe(false);
  });
});
