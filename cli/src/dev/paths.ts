export type Resolved =
  | { kind: "file"; path: string }
  | { kind: "redirect"; location: string }
  | { kind: "events" }
  | { kind: "not found" };

export const eventsSuffix = "_sheaf/dev/events";

/**
 * Maps a request path to a file in the output folder. Anything that could
 * name a file outside the folder is "not found" rather than sanitised, so
 * a crafted URL never reads something the site didn't generate.
 */
export function resolveRequest(basePath: string, pathname: string): Resolved {
  if (basePath !== "/" && (pathname === "/" || `${pathname}/` === basePath)) {
    return { kind: "redirect", location: basePath };
  }
  if (!pathname.startsWith(basePath)) {
    return { kind: "not found" };
  }
  const requested = pathname.slice(basePath.length);
  if (requested === eventsSuffix) {
    return { kind: "events" };
  }

  const decoded = decode(requested);
  if (decoded === undefined || escapesFolder(decoded)) {
    return { kind: "not found" };
  }
  const path =
    decoded === "" || decoded.endsWith("/") ? `${decoded}index.html` : decoded;
  return { kind: "file", path };
}

function decode(requested: string): string | undefined {
  try {
    return decodeURIComponent(requested);
  } catch (error) {
    if (error instanceof URIError) {
      return undefined;
    }
    throw error;
  }
}

function escapesFolder(decoded: string): boolean {
  return (
    decoded.startsWith("/") ||
    decoded.includes("\\") ||
    decoded.includes("\0") ||
    decoded.split("/").includes("..")
  );
}
