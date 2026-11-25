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

  test("accepts images, which are not used yet", () => {
    const result = parse('{"siteUrl":"https://example.com/","images":{}}');
    expect(result.ok).toBe(true);
  });

  test("highlights with the GitHub themes by default", () => {
    for (const json of [
      '{"siteUrl":"https://example.com/"}',
      '{"siteUrl":"https://example.com/","highlight":{}}',
      '{"siteUrl":"https://example.com/","highlight":{"theme":{}}}',
    ]) {
      const result = parse(json);
      expect(result.ok && result.value.highlight).toEqual({
        light: "github-light",
        dark: "github-dark",
      });
    }
  });

  test("keeps the highlight themes it is given", () => {
    const result = parse(
      '{"siteUrl":"https://example.com/","highlight":{"theme":{"dark":"nord"}}}',
    );
    expect(result.ok && result.value.highlight).toEqual({
      light: "github-light",
      dark: "nord",
    });
  });

  test("suggests the Shiki theme closest to an unknown one", () => {
    const errors = errorsOf(
      '{"siteUrl":"https://example.com/","highlight":{"theme":{"light":"github-lite"}}}',
    );
    expect(errors).toHaveLength(1);
    expect(errors[0]?.title).toBe("BAD CONFIG");
    expect(errors[0]?.message).toContain("github-lite");
    expect(errors[0]?.hint).toContain('"github-light"');
  });

  test("rejects unknown keys and wrong types under highlight", () => {
    const errors = errorsOf(
      '{"siteUrl":"https://example.com/","highlight":{"themes":{},"theme":{"light":1,"darkk":"nord"}}}',
    );
    expect(errors.map(({ hint }) => hint)).toEqual([
      'Did you mean "theme"?',
      'Did you mean "dark"?',
      undefined,
    ]);
    expect(errors[2]?.message).toBe(
      '"highlight.theme.light" must be a string.',
    );
  });

  test("rejects a highlight that is not an object", () => {
    const errors = errorsOf(
      '{"siteUrl":"https://example.com/","highlight":"github-dark"}',
    );
    expect(errors[0]?.message).toBe('"highlight" must be an object.');
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

  test("rejects a siteUrl with a query or a fragment", () => {
    for (const siteUrl of [
      "https://example.com/?x=1",
      "https://example.com/#top",
    ]) {
      const errors = errorsOf(`{"siteUrl":"${siteUrl}"}`);
      expect(errors).toHaveLength(1);
      expect(errors[0]?.title).toBe("BAD CONFIG");
      expect(errors[0]?.hint).toBe(
        'Write the site\'s address without "?" or "#", such as https://example.com/blog/.',
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
