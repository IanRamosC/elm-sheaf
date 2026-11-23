import { describe, expect, test } from "bun:test";
import { parseConfig } from "../../src/config/config";

function parse(json: string) {
  return parseConfig(json, "sheaf.json");
}

function errorsOf(json: string) {
  const result = parse(json);
  if (result.ok) throw new Error("expected the config to be rejected");
  return result.error;
}

describe("parseConfig", () => {
  test("derives the base path from the site URL and defaults the timezone", () => {
    const result = parse('{"siteUrl":"https://example.com/blog"}');
    expect(result.ok && result.value.basePath).toBe("/blog/");
    expect(result.ok && result.value.timezone).toBe("UTC");
    expect(result.ok && result.value.siteUrl.href).toBe(
      "https://example.com/blog",
    );
  });

  test("uses / as the base path for a site at the domain root", () => {
    const result = parse('{"siteUrl":"https://example.com"}');
    expect(result.ok && result.value.basePath).toBe("/");
  });

  test("keeps a base path that already ends with a slash", () => {
    const result = parse('{"siteUrl":"https://example.com/blog/"}');
    expect(result.ok && result.value.basePath).toBe("/blog/");
  });

  test("keeps a valid timezone", () => {
    const result = parse(
      '{"siteUrl":"https://example.com/","timezone":"Europe/Lisbon"}',
    );
    expect(result.ok && result.value.timezone).toBe("Europe/Lisbon");
  });

  test("accepts highlight and images, which are not used yet", () => {
    const result = parse(
      '{"siteUrl":"https://example.com/","highlight":{},"images":{}}',
    );
    expect(result.ok).toBe(true);
  });

  test("requires siteUrl", () => {
    const errors = errorsOf("{}");
    expect(errors).toHaveLength(1);
    expect(errors[0]?.title).toBe("BAD CONFIG");
    expect(errors[0]?.message).toContain("siteUrl");
    expect(errors[0]?.sourcePath).toBe("sheaf.json");
  });

  test("rejects a siteUrl that is not a full URL", () => {
    const errors = errorsOf('{"siteUrl":"example.com"}');
    expect(errors).toHaveLength(1);
    expect(errors[0]?.hint).toBe("Use a full URL such as https://example.com/");
  });

  test("rejects a host and port written without a scheme", () => {
    for (const siteUrl of ["localhost:3000", "example.com:8080"]) {
      const errors = errorsOf(`{"siteUrl":"${siteUrl}"}`);
      expect(errors).toHaveLength(1);
      expect(errors[0]?.hint).toBe(
        "Use a full URL such as https://example.com/",
      );
    }
  });

  test("rejects a siteUrl that is not a string", () => {
    expect(errorsOf('{"siteUrl":42}')).toHaveLength(1);
  });

  test("rejects an unknown timezone", () => {
    const errors = errorsOf(
      '{"siteUrl":"https://example.com/","timezone":"Mars/Base"}',
    );
    expect(errors).toHaveLength(1);
    expect(errors[0]?.message).toContain("Mars/Base");
  });

  test("suggests the known key closest to an unknown one", () => {
    const errors = errorsOf(
      '{"siteurl":"https://example.com/","siteUrl":"https://example.com/"}',
    );
    expect(errors).toHaveLength(1);
    expect(errors[0]?.message).toContain("siteurl");
    expect(errors[0]?.hint).toContain("siteUrl");
  });

  test("reports an unknown key without a hint when nothing is close", () => {
    const errors = errorsOf(
      '{"siteUrl":"https://example.com/","analytics":true}',
    );
    expect(errors[0]?.hint).toBeUndefined();
  });

  test("rejects invalid JSON", () => {
    const errors = errorsOf("{ not json");
    expect(errors).toHaveLength(1);
    expect(errors[0]?.title).toBe("BAD CONFIG");
  });

  test("rejects JSON that is not an object", () => {
    expect(errorsOf("[]")).toHaveLength(1);
  });

  test("returns every problem in the file together", () => {
    const errors = errorsOf('{"siteUrl":"nope","timezone":"Mars/Base","x":1}');
    expect(errors).toHaveLength(3);
  });
});
