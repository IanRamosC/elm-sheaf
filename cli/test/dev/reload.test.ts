import { describe, expect, test } from "bun:test";
import { errorPage } from "../../src/dev/error-page";
import { withReloadScript } from "../../src/dev/reload";

const events = "/blog/_sheaf/dev/events";

describe("withReloadScript", () => {
  test("inserts the script before the closing body tag", () => {
    const html = withReloadScript("<p>x</p></body></html>", events);

    expect(html).toMatch(
      /^<p>x<\/p><script type="module">.*<\/script><\/body><\/html>$/s,
    );
    expect(html).toContain(events);
  });

  test("uses the last closing body tag", () => {
    const html = withReloadScript("<pre>&lt;/body></pre></body>", events);

    expect(html.indexOf("<script")).toBeGreaterThan(html.indexOf("</pre>"));
  });

  test("appends the script when there is no closing body tag", () => {
    expect(withReloadScript("<p>x</p>", events)).toStartWith("<p>x</p><script");
  });
});

describe("errorPage", () => {
  test("escapes each diagnostic inside a pre element", () => {
    const html = errorPage(["-- BROKEN LINK -- <a>", "second"], events);

    expect(html).toContain("<pre>-- BROKEN LINK -- &lt;a&gt;</pre>");
    expect(html).toContain("<pre>second</pre>");
  });

  test("reloads itself when the next build finishes", () => {
    expect(errorPage([], events)).toContain(events);
  });
});
