import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { type DevServer, startDevServer } from "../../src/dev/server";

let folder: string;
const servers: DevServer[] = [];

beforeEach(() => {
  folder = mkdtempSync(join(tmpdir(), "sheaf-dev-"));
  writeFileSync(join(folder, "index.html"), "<html><body>home</body></html>");
  writeFileSync(join(folder, "style.css"), "body{}");
  mkdirSync(join(folder, "about"));
  writeFileSync(join(folder, "about", "index.html"), "<body>about</body>");
});

afterEach(() => {
  for (const server of servers.splice(0)) {
    server.stop();
  }
  rmSync(folder, { recursive: true, force: true });
});

function start(port: number | undefined = 0): DevServer {
  const started = startDevServer({ basePath: "/blog/", port });
  if (!started.ok) {
    throw new Error(started.error);
  }
  servers.push(started.value);
  return started.value;
}

describe("startDevServer", () => {
  test("serves the site under its base path with the reload script in pages", async () => {
    const server = start();
    server.showSite(folder);

    const page = await fetch(server.url);

    expect(page.status).toBe(200);
    expect(page.headers.get("cache-control")).toBe("no-store");
    expect(await page.text()).toMatch(/home<script type="module">.*<\/body>/s);
  });

  test("serves other files untouched", async () => {
    const server = start();
    server.showSite(folder);

    const css = await fetch(`${server.url}style.css`);

    expect(css.headers.get("content-type")).toStartWith("text/css");
    expect(await css.text()).toBe("body{}");
  });

  test("answers a missing page with 404.html, or plain text without one", async () => {
    const server = start();
    server.showSite(folder);

    const plain = await fetch(`${server.url}missing/`);
    expect(plain.status).toBe(404);
    expect(plain.headers.get("content-type")).toStartWith("text/plain");

    writeFileSync(join(folder, "404.html"), "<body>gone</body>");
    const page = await fetch(`${server.url}missing/`);
    expect(page.status).toBe(404);
    expect(await page.text()).toContain("gone<script");
  });

  test("redirects a folder to its slash and the root to the base path", async () => {
    const server = start();
    server.showSite(folder);
    const origin = new URL(server.url).origin;

    const folderResponse = await fetch(`${origin}/blog/about`, {
      redirect: "manual",
    });
    expect(folderResponse.status).toBe(302);
    expect(folderResponse.headers.get("location")).toBe("/blog/about/");

    const root = await fetch(`${origin}/`, { redirect: "manual" });
    expect(root.headers.get("location")).toBe("/blog/");
  });

  test("never serves a file outside the output folder", async () => {
    writeFileSync(join(folder, "..", "sheaf-secret.json"), "{}");
    const server = start();
    server.showSite(folder);
    const origin = new URL(server.url).origin;

    try {
      for (const path of [
        "/blog/..%2fsheaf-secret.json",
        "/blog/%2e%2e/sheaf-secret.json",
      ]) {
        expect((await fetch(origin + path)).status).toBe(404);
      }
    } finally {
      rmSync(join(folder, "..", "sheaf-secret.json"));
    }
  });

  test("shows a building page until the first build finishes", async () => {
    const server = start();

    const page = await fetch(server.url);

    expect(page.status).toBe(503);
    expect(await page.text()).toContain("Building");
  });

  test("shows the diagnostics for pages and keeps serving the last good files", async () => {
    const server = start();
    server.showSite(folder);
    server.showErrors(["-- BROKEN LINK -- <a>"]);

    const page = await fetch(server.url);
    expect(page.status).toBe(500);
    expect(await page.text()).toContain("&lt;a&gt;");

    expect(await (await fetch(`${server.url}style.css`)).text()).toBe("body{}");
  });

  test("shows the diagnostics for every request when no build has succeeded", async () => {
    const server = start();
    server.showErrors(["broken"]);

    expect((await fetch(`${server.url}style.css`)).status).toBe(500);
  });

  test("tells a connected client to reload", async () => {
    const server = start();
    const response = await fetch(`${server.url}_sheaf/dev/events`);
    expect(response.headers.get("content-type")).toStartWith(
      "text/event-stream",
    );

    server.reload();

    expect(await readUntil(response, "event: reload")).toBe(true);
  });

  test("keeps an idle events stream open past Bun's 10 second timeout", async () => {
    const server = start();
    const response = await fetch(`${server.url}_sheaf/dev/events`);
    const received = readUntil(response, "event: reload");

    await Bun.sleep(12_000);
    server.reload();

    expect(await received).toBe(true);
  }, 20_000);

  test("reports a busy port by number", () => {
    const first = start();
    const port = Number(new URL(first.url).port);

    const second = startDevServer({ basePath: "/", port });

    expect(second.ok).toBe(false);
    expect(!second.ok && second.error).toContain(String(port));
  });
});

async function readUntil(response: Response, text: string): Promise<boolean> {
  const reader = response.body?.getReader();
  if (reader === undefined) {
    return false;
  }
  const decoder = new TextDecoder();
  let received = "";
  while (!received.includes(text)) {
    const { done, value } = await reader.read();
    if (done) {
      return false;
    }
    received += decoder.decode(value);
  }
  await reader.cancel();
  return true;
}
