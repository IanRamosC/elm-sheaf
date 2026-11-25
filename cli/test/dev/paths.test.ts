import { describe, expect, test } from "bun:test";
import { resolveRequest } from "../../src/dev/paths";

describe("resolveRequest", () => {
  test("serves the index of a folder", () => {
    expect(resolveRequest("/blog/", "/blog/")).toEqual({
      kind: "file",
      path: "index.html",
    });
    expect(resolveRequest("/blog/", "/blog/posts/a/")).toEqual({
      kind: "file",
      path: "posts/a/index.html",
    });
  });

  test("serves a path as the file it names", () => {
    expect(resolveRequest("/", "/")).toEqual({
      kind: "file",
      path: "index.html",
    });
    expect(resolveRequest("/", "/about")).toEqual({
      kind: "file",
      path: "about",
    });
    expect(resolveRequest("/blog/", "/blog/style.css")).toEqual({
      kind: "file",
      path: "style.css",
    });
  });

  test("redirects the root and the base path without its slash", () => {
    expect(resolveRequest("/blog/", "/")).toEqual({
      kind: "redirect",
      location: "/blog/",
    });
    expect(resolveRequest("/blog/", "/blog")).toEqual({
      kind: "redirect",
      location: "/blog/",
    });
  });

  test("finds the events endpoint under the base path", () => {
    expect(resolveRequest("/blog/", "/blog/_sheaf/dev/events")).toEqual({
      kind: "events",
    });
  });

  test("never leaves the output folder", () => {
    for (const pathname of [
      "/blog/%2e%2e/sheaf.json",
      "/blog/..%2fsheaf.json",
      "/blog/..%5Csheaf.json",
      "/blog/a/%2E%2E/%2E%2E/x",
      "/blog/a%00b",
      "/blog/%2Fetc/passwd",
      "/other/index.html",
      "/blog/%E0%A4%A",
    ]) {
      expect(resolveRequest("/blog/", pathname)).toEqual({ kind: "not found" });
    }
  });
});
