import { withReloadScript } from "./reload";

export function escapeHtml(text: string): string {
  return text
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");
}

export function errorPage(rendered: string[], eventsPath: string): string {
  const diagnostics = rendered
    .map((text) => `<pre>${escapeHtml(text)}</pre>`)
    .join("\n");
  return withReloadScript(page("Build failed", diagnostics), eventsPath);
}

export function buildingPage(eventsPath: string): string {
  return withReloadScript(page("Building…", "<p>Building…</p>"), eventsPath);
}

function page(title: string, body: string): string {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title}</title>
<style>body{font-family:system-ui,sans-serif;margin:2rem}pre{overflow-x:auto;white-space:pre-wrap}</style>
</head>
<body>
<h1>${title}</h1>
${body}
</body>
</html>
`;
}
