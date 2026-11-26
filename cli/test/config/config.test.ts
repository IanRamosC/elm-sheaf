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

  test("lets a siteUrl override replace the one in the file", () => {
    const result = parseConfig(
      '{"siteUrl":"https://a.example/"}',
      "sheaf.json",
      {
        siteUrl: "https://user.github.io/repo/",
      },
    );

    expect(result.ok && result.value.basePath).toBe("/repo/");
    expect(result.ok && result.value.siteUrl.href).toBe(
      "https://user.github.io/repo/",
    );
  });

  test("rejects a siteUrl override with a query, naming the flag and no file", () => {
    const result = parseConfig(
      '{"siteUrl":"https://a.example/"}',
      "sheaf.json",
      {
        siteUrl: "https://user.github.io/repo/?x=1",
      },
    );

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.error).toHaveLength(1);
    expect(result.error[0]?.title).toBe("BAD CONFIG");
    expect(result.error[0]?.message).toContain("--site-url");
    expect(result.error[0]).not.toHaveProperty("sourcePath");
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

  test("resizes images to three widths and writes WebP by default", () => {
    for (const json of [
      '{"siteUrl":"https://example.com/"}',
      '{"siteUrl":"https://example.com/","images":{}}',
    ]) {
      const result = parse(json);
      expect(result.ok && result.value.images).toEqual({
        widths: [480, 960, 1600],
        formats: ["webp"],
      });
    }
  });

  test("keeps the image widths and formats it is given", () => {
    const result = parse(
      '{"siteUrl":"https://example.com/","images":{"widths":[640],"formats":[]}}',
    );
    expect(result.ok && result.value.images).toEqual({
      widths: [640],
      formats: [],
    });
  });

  test("rejects image widths that are not positive whole numbers", () => {
    for (const widths of ["[]", "[0]", "[-480]", "[480.5]", '["480"]', "480"]) {
      const [problem] = errorsOf(
        `{"siteUrl":"https://example.com/","images":{"widths":${widths}}}`,
      );
      expect(problem?.title).toBe("BAD CONFIG");
      expect(problem?.message).toContain('"images.widths"');
    }
  });

  test("explains that AVIF cannot be written", () => {
    expect(
      errorsOf(
        '{"siteUrl":"https://example.com/","images":{"formats":["webp","avif"]}}',
      ),
    ).toEqual([
      {
        severity: "error",
        title: "BAD CONFIG",
        message: '"images.formats" asks for AVIF.',
        sourcePath: "sheaf.json",
        hint: 'Sheaf writes WebP variants only: Bun\'s image encoder can\'t write AVIF on Linux, where most sites are built. Use "formats": ["webp"].',
      },
    ]);
  });

  test("rejects unknown image formats and keys", () => {
    const problems = errorsOf(
      '{"siteUrl":"https://example.com/","images":{"widht":[1],"formats":["png"]}}',
    );
    expect(problems.map(({ message, hint }) => ({ message, hint }))).toEqual([
      {
        message: 'I do not know the key "images.widht".',
        hint: 'Did you mean "widths"?',
      },
      {
        message:
          '"png" in "images.formats" is not an image format Sheaf writes.',
        hint: 'Use "formats": ["webp"].',
      },
    ]);
  });

  test("highlights with the GitHub themes by default", () => {
    for (const json of [
      '{"siteUrl":"https://example.com/"}',
      '{"siteUrl":"https://example.com/","highlight":{}}',
      '{"siteUrl":"https://example.com/","highlight":{"theme":{}}}',
    ]) {
      const result = parse(json);
      expect(result.ok && result.value.highlight).toEqual({
        theme: { light: "github-light", dark: "github-dark" },
        grammars: new Map(),
        themes: new Map(),
      });
    }
  });

  test("keeps the highlight themes it is given", () => {
    const result = parse(
      '{"siteUrl":"https://example.com/","highlight":{"theme":{"dark":"nord"}}}',
    );
    expect(result.ok && result.value.highlight.theme).toEqual({
      light: "github-light",
      dark: "nord",
    });
  });

  test("keeps the site's own grammars and themes", () => {
    const result = parse(
      JSON.stringify({
        siteUrl: "https://example.com/",
        highlight: {
          theme: { dark: "my-theme" },
          grammars: { nginx: "highlight/nginx.tmLanguage.json" },
          themes: { "my-theme": "highlight/my-theme.json" },
        },
      }),
    );
    expect(result.ok && result.value.highlight).toEqual({
      theme: { light: "github-light", dark: "my-theme" },
      grammars: new Map([["nginx", "highlight/nginx.tmLanguage.json"]]),
      themes: new Map([["my-theme", "highlight/my-theme.json"]]),
    });
  });

  test("lets a site theme take the name of a theme Sheaf leaves out", () => {
    const result = parse(
      '{"siteUrl":"https://example.com/","highlight":{"theme":{"dark":"aurora-x"},"themes":{"aurora-x":"aurora-x.json"}}}',
    );
    expect(result.ok && result.value.highlight.theme.dark).toBe("aurora-x");
  });

  test("suggests the site's own theme", () => {
    const errors = errorsOf(
      '{"siteUrl":"https://example.com/","highlight":{"theme":{"dark":"my-thme"},"themes":{"my-theme":"t.json"}}}',
    );
    expect(errors[0]?.hint).toBe('Did you mean "my-theme"?');
  });

  test("rejects grammars and themes that are not objects of paths", () => {
    const errors = errorsOf(
      '{"siteUrl":"https://example.com/","highlight":{"grammars":["nginx"],"themes":{"mine":1}}}',
    );
    expect(
      errors.map(({ title, message, sourcePath }) => [
        title,
        message,
        sourcePath,
      ]),
    ).toEqual([
      ["BAD CONFIG", '"highlight.grammars" must be an object.', "sheaf.json"],
      ["BAD CONFIG", '"highlight.themes.mine" must be a string.', "sheaf.json"],
    ]);
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

  test("says why a GPL theme is left out", () => {
    const errors = errorsOf(
      '{"siteUrl":"https://example.com/","highlight":{"theme":{"dark":"aurora-x"}}}',
    );
    expect(errors).toEqual([
      {
        severity: "error",
        title: "BAD CONFIG",
        message: 'The dark theme "aurora-x" is not a theme Sheaf can use.',
        sourcePath: "sheaf.json",
        hint: "Shiki's aurora-x theme is GPL-3.0, so Sheaf doesn't include it. Add it to your site with \"highlight.themes\" in sheaf.json.",
      },
    ]);
  });

  test("never suggests a theme it leaves out", () => {
    const errors = errorsOf(
      '{"siteUrl":"https://example.com/","highlight":{"theme":{"dark":"aurora-xx"}}}',
    );
    expect(errors[0]?.hint).not.toContain("aurora-x");
  });

  test("rejects unknown keys and wrong types under highlight", () => {
    const errors = errorsOf(
      '{"siteUrl":"https://example.com/","highlight":{"theem":{},"theme":{"light":1,"darkk":"nord"}}}',
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
