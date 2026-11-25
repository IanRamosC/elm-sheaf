/** An SVG's size in CSS pixels. */
export type SvgSize = { width: number; height: number };

// What may come before the root element: a byte order mark, whitespace, the
// XML declaration, comments and a doctype.
const PROLOG = /^﻿?(?:\s+|<\?xml[\s\S]*?\?>|<!--[\s\S]*?-->|<!DOCTYPE[^>]*>)*/i;
const ROOT_TAG = /^<svg(?=[\s/>])([^>]*)>/;
const ATTRIBUTE = /([\w:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')/g;
const PIXELS = /^\s*(\d+(?:\.\d+)?)\s*(?:px)?\s*$/;

/** Whether `text` is an SVG document, which `Bun.Image` cannot read. */
export function isSvg(text: string): boolean {
  return rootAttributes(text) !== undefined;
}

/**
 * The size of an SVG, from its `width` and `height` when both are unitless or
 * in pixels, and otherwise from its `viewBox`. Without either, an `<img>`
 * could not reserve space for it.
 */
export function svgSize(text: string): SvgSize | undefined {
  const attributes = rootAttributes(text);
  if (attributes === undefined) return undefined;
  const width = pixels(attributes.get("width"));
  const height = pixels(attributes.get("height"));
  if (width !== undefined && height !== undefined) return { width, height };
  const viewBox = attributes
    .get("viewBox")
    ?.trim()
    .split(/[\s,]+/)
    .map(Number);
  if (viewBox?.length !== 4) return undefined;
  const [, , boxWidth = 0, boxHeight = 0] = viewBox;
  const size = { width: Math.round(boxWidth), height: Math.round(boxHeight) };
  return size.width > 0 && size.height > 0 ? size : undefined;
}

function rootAttributes(text: string): Map<string, string> | undefined {
  const root = ROOT_TAG.exec(text.replace(PROLOG, ""));
  if (root === null) return undefined;
  const attributes = new Map<string, string>();
  for (const [, name = "", double, single] of (root[1] ?? "").matchAll(
    ATTRIBUTE,
  )) {
    attributes.set(name, double ?? single ?? "");
  }
  return attributes;
}

function pixels(value: string | undefined): number | undefined {
  const match = value === undefined ? null : PIXELS.exec(value);
  const size = match === null ? 0 : Math.round(Number(match[1]));
  return size > 0 ? size : undefined;
}
