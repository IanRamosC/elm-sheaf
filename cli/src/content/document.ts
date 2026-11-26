import type { DocumentDate } from "./dates";
import type { FieldPosition } from "./frontmatter";

/**
 * A document's own image, from `image: cover.png` or
 * `image: { src: cover.png, alt: "…" }`. `src` is a path or an http(s) URL.
 */
export type CoverImage = { src: string; alt: string };

/**
 * One Markdown document as it is read from disk, with the host's reserved
 * frontmatter keys resolved. Everything later stages need to know about a
 * document starts here.
 */
export type SourceDocument = {
  /** `"<collection>/<slug>"`, unique across the site. */
  id: string;
  collection: string;
  /** Path relative to the site root, with `/` separators. */
  sourcePath: string;
  slug: string;
  date?: DocumentDate;
  updated?: DocumentDate;
  draft: boolean;
  /** Left out of this build because it is a draft or dated in the future. */
  excluded: boolean;
  /** The `image` key, which is resolved like an image in the body. */
  image?: CoverImage;
  /**
   * The `aliases` key: other paths on the site, such as `/2019/old-name/`,
   * that redirect to this document. Without the base path.
   */
  aliases: string[];
  /** The user's own fields: every key except the reserved ones. */
  frontmatter: Record<string, unknown>;
  frontmatterPositions: FieldPosition[];
  body: string;
  /** The 1-based file line on which `body` begins. */
  bodyStartLine: number;
};
