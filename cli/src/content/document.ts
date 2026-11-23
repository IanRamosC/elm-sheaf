import type { DocumentDate } from "./dates";
import type { FieldPosition } from "./frontmatter";

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
  /** The raw `image` value; it is not processed until images are supported. */
  imageSource?: string;
  /** The user's own fields: every key except the reserved ones. */
  frontmatter: Record<string, unknown>;
  frontmatterPositions: Record<string, FieldPosition>;
  body: string;
  /** The 1-based file line on which `body` begins. */
  bodyStartLine: number;
};
