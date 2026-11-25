import { stat } from "node:fs/promises";
import { join } from "node:path";
import { err, ok, type Result } from "../result";
import { buildingPage, errorPage } from "./error-page";
import { eventsSuffix, resolveRequest } from "./paths";
import { withReloadScript } from "./reload";

export type DevServer = {
  url: string;
  /** Serves the site in `folder` from the next request on. */
  showSite(folder: string): void;
  /** Answers page requests with the diagnostics until the next `showSite`. */
  showErrors(rendered: string[]): void;
  /** Tells every connected browser to reload. */
  reload(): void;
  stop(): void;
};

type Options = { basePath: string; port: number | undefined };

type State =
  | { kind: "building" }
  | { kind: "site"; folder: string }
  | { kind: "failed"; rendered: string[]; lastGood: string | undefined };

const defaultPorts = { first: 4000, last: 4010 };
const pingMilliseconds = 5000;
const headers = { "Cache-Control": "no-store" };

export function startDevServer(options: Options): Result<DevServer, string> {
  const { basePath } = options;
  const eventsPath = basePath + eventsSuffix;
  const encoder = new TextEncoder();
  const clients = new Set<ReadableStreamDefaultController<Uint8Array>>();
  let state: State = { kind: "building" };

  function send(message: string): void {
    for (const client of clients) {
      client.enqueue(encoder.encode(message));
    }
  }

  // A comment line keeps proxies and Bun from treating the stream as dead.
  const pings = setInterval(() => send(": ping\n\n"), pingMilliseconds);

  function events(request: Request, server: Bun.Server<undefined>): Response {
    server.timeout(request, 0);
    let client: ReadableStreamDefaultController<Uint8Array>;
    const body = new ReadableStream<Uint8Array>({
      start(controller) {
        client = controller;
        clients.add(controller);
        controller.enqueue(encoder.encode(": connected\n\n"));
      },
      cancel() {
        clients.delete(client);
      },
    });
    return new Response(body, {
      headers: { ...headers, "Content-Type": "text/event-stream" },
    });
  }

  async function serve(
    request: Request,
    server: Bun.Server<undefined>,
  ): Promise<Response> {
    const { pathname } = new URL(request.url);
    const resolved = resolveRequest(basePath, pathname);
    switch (resolved.kind) {
      case "events":
        return events(request, server);
      case "redirect":
        return redirect(resolved.location);
      case "not found":
        return notFound(state);
      case "file":
        return serveFile(resolved.path, pathname);
    }
  }

  async function serveFile(path: string, pathname: string): Promise<Response> {
    const isPage = path.endsWith(".html");
    switch (state.kind) {
      case "building":
        return isPage ? html(buildingPage(eventsPath), 503) : plainNotFound();
      case "failed":
        if (state.lastGood === undefined || isPage) {
          return html(errorPage(state.rendered, eventsPath), 500);
        }
        return fromFolder(state.lastGood, path, pathname);
      case "site":
        return fromFolder(state.folder, path, pathname);
    }
  }

  // The redirect keeps the request's own encoding: a decoded path breaks on non-ASCII and on "?".
  async function fromFolder(
    folder: string,
    path: string,
    pathname: string,
  ): Promise<Response> {
    const file = join(folder, path);
    if (await isFile(file)) {
      return path.endsWith(".html")
        ? html(withReloadScript(await Bun.file(file).text(), eventsPath), 200)
        : new Response(Bun.file(file), { headers });
    }
    if (await isFile(join(file, "index.html"))) {
      return redirect(`${pathname}/`);
    }
    return notFound(state);
  }

  async function notFound(current: State): Promise<Response> {
    const folder = servedFolder(current);
    const page = folder === undefined ? undefined : join(folder, "404.html");
    if (page !== undefined && (await isFile(page))) {
      return html(
        withReloadScript(await Bun.file(page).text(), eventsPath),
        404,
      );
    }
    return plainNotFound();
  }

  function plainNotFound(): Response {
    return new Response("Not found", {
      status: 404,
      headers: { ...headers, "Content-Type": "text/plain; charset=utf-8" },
    });
  }

  function html(body: string, status: number): Response {
    return new Response(body, {
      status,
      headers: { ...headers, "Content-Type": "text/html; charset=utf-8" },
    });
  }

  function redirect(location: string): Response {
    return new Response(null, {
      status: 302,
      headers: { ...headers, Location: location },
    });
  }

  const started = listen(options.port, serve);
  if (!started.ok) {
    clearInterval(pings);
    return started;
  }
  const server = started.value;

  return ok({
    url: `http://127.0.0.1:${server.port}${basePath}`,
    showSite(folder) {
      state = { kind: "site", folder };
    },
    showErrors(rendered) {
      state = { kind: "failed", rendered, lastGood: servedFolder(state) };
    },
    reload() {
      send("event: reload\ndata: reload\n\n");
    },
    stop() {
      clearInterval(pings);
      for (const client of clients) {
        client.close();
      }
      clients.clear();
      server.stop(true);
    },
  });
}

function servedFolder(state: State): string | undefined {
  switch (state.kind) {
    case "site":
      return state.folder;
    case "failed":
      return state.lastGood;
    case "building":
      return undefined;
  }
}

type Handler = (
  request: Request,
  server: Bun.Server<undefined>,
) => Promise<Response>;

/** Binds to 127.0.0.1 explicitly: `localhost` would hide a busy port by falling back to another address. */
function listen(
  port: number | undefined,
  fetch: Handler,
): Result<Bun.Server<undefined>, string> {
  const candidates =
    port === undefined
      ? Array.from(
          { length: defaultPorts.last - defaultPorts.first + 1 },
          (_, i) => defaultPorts.first + i,
        )
      : [port];
  for (const candidate of candidates) {
    try {
      return ok(Bun.serve({ hostname: "127.0.0.1", port: candidate, fetch }));
    } catch (error) {
      if (!isAddressInUse(error)) {
        throw error;
      }
    }
  }
  return err(
    port === undefined
      ? `Ports ${defaultPorts.first} to ${defaultPorts.last} are all in use. Free one, or pick another with --port.`
      : `Port ${port} is already in use. Pick another with --port.`,
  );
}

function isAddressInUse(error: unknown): boolean {
  return (
    error instanceof Error && "code" in error && error.code === "EADDRINUSE"
  );
}

async function isFile(path: string): Promise<boolean> {
  try {
    return (await stat(path)).isFile();
  } catch {
    return false;
  }
}
