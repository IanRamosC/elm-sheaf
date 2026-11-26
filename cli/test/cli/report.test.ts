import { describe, expect, test } from "bun:test";
import { pagesSummary } from "../../src/cli/report";

describe("pagesSummary", () => {
  test("mentions redirects only when there are any", () => {
    expect(pagesSummary(12, 0)).toBe("12 pages");
    expect(pagesSummary(1, 0)).toBe("1 page");
    expect(pagesSummary(12, 2)).toBe("12 pages and 2 redirects");
    expect(pagesSummary(1, 1)).toBe("1 page and 1 redirect");
  });
});
