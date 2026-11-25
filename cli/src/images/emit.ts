import type { OutputFile } from "../emit/write";
import type { ImageFile } from "./resolve";

/**
 * Copies of the cached files into `dist/`. Documents that use one image, and
 * files with identical bytes, share their outputs, so each path is copied once.
 */
export function imageOutputs(files: ImageFile[]): OutputFile[] {
  const byPath = new Map<string, OutputFile>();
  for (const { cached, path } of files) {
    byPath.set(path, { kind: "copy", path, source: cached });
  }
  return [...byPath.values()];
}
