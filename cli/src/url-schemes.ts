/**
 * URL schemes that Markdown links pass through unchecked. A collection may
 * not take one of these names, so `<collection>:<slug>` can never be mistaken
 * for a URL.
 */
export const URL_SCHEMES = [
  "http",
  "https",
  "mailto",
  "tel",
  "sms",
  "ftp",
  "data",
  "file",
];
