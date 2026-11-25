/**
 * Reloads the page when the dev server announces a build. It lives only in
 * served responses, so the files on disk stay free of JavaScript.
 */
function reloadScript(eventsPath: string): string {
  const url = JSON.stringify(eventsPath).replaceAll("<", "\\u003c");
  return `<script type="module">new EventSource(${url}).addEventListener("reload", () => location.reload());</script>`;
}

export function withReloadScript(html: string, eventsPath: string): string {
  const script = reloadScript(eventsPath);
  const end = html.lastIndexOf("</body>");
  return end === -1
    ? html + script
    : html.slice(0, end) + script + html.slice(end);
}
