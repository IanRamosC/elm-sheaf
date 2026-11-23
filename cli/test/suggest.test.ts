import { expect, test } from "bun:test";
import { suggestions } from "../src/suggest";

const known = ["siteUrl", "timezone", "highlight", "images"];

test("suggests the closest candidate for a near miss", () => {
  expect(suggestions("siteurl", known, 3)).toEqual(["siteUrl"]);
});

test("orders suggestions from closest to farthest", () => {
  expect(suggestions("imges", ["images", "image", "tags"], 3)).toEqual([
    "images",
    "image",
  ]);
});

test("offers nothing when no candidate is close", () => {
  expect(suggestions("completely-different", known, 3)).toEqual([]);
});

test("honours the limit", () => {
  expect(suggestions("post", ["posts", "poste", "postz"], 2)).toHaveLength(2);
});
