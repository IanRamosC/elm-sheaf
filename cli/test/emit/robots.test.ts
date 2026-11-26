import { describe, expect, test } from "bun:test";
import { providesRobots, robotsTxt } from "../../src/emit/robots";

describe("robotsTxt", () => {
  test("names the sitemap", () => {
    expect(robotsTxt("https://x.y/repo/sitemap.xml")).toBe(
      "User-agent: *\nAllow: /\n\nSitemap: https://x.y/repo/sitemap.xml\n",
    );
  });
});

describe("providesRobots", () => {
  test("finds the file and a folder of that name, in any case", () => {
    expect(providesRobots(["robots.txt"])).toBe(true);
    expect(providesRobots(["Robots.TXT"])).toBe(true);
    expect(providesRobots(["robots.txt/index.html"])).toBe(true);
  });

  test("ignores other paths", () => {
    expect(
      providesRobots(["index.html", "docs/robots.txt", "robots.txt.bak"]),
    ).toBe(false);
  });
});
