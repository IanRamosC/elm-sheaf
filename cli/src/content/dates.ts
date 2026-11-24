import { err, ok, type Result } from "../result";

/** A publication or update date: the moment it denotes, and the calendar date as written. */
export type DocumentDate = { instant: Date; isoDate: string };

const DATE_ONLY = /^(\d{4})-(\d{2})-(\d{2})$/;
const TIMESTAMP_WITH_OFFSET =
  /^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?(?:Z|[+-]\d{2}:\d{2})$/;
const MINUTE = 60_000;

/**
 * Resolves a `date` or `updated` value. `YYYY-MM-DD` means midnight in
 * `timezone`; a full timestamp must carry its own offset and is taken as given.
 */
export function publicationInstant(
  date: string,
  timezone: string,
): Result<Date, string> {
  const dateOnly = DATE_ONLY.exec(date);
  if (dateOnly) {
    return midnightIn(
      timezone,
      Number(dateOnly[1]),
      Number(dateOnly[2]),
      Number(dateOnly[3]),
    );
  }
  const timestamp = TIMESTAMP_WITH_OFFSET.exec(date);
  if (timestamp) {
    // `new Date` rolls impossible values over (February 30th becomes March
    // 2nd, 24:00 the next day), so the parts are checked first.
    const second = Number(timestamp[6] ?? 0);
    const instant = new Date(date);
    if (
      isCalendarDate(
        Number(timestamp[1]),
        Number(timestamp[2]),
        Number(timestamp[3]),
      ) &&
      Number(timestamp[4]) <= 23 &&
      Number(timestamp[5]) <= 59 &&
      second <= 59 &&
      !Number.isNaN(instant.getTime())
    ) {
      return ok(instant);
    }
  }
  return err(
    `"${date}" is not a date. Write YYYY-MM-DD, or a timestamp with an offset such as 2026-11-30T10:00:00+02:00.`,
  );
}

/** Like {@link publicationInstant}, and also keeps the calendar date as the author wrote it. */
export function publicationDate(
  date: string,
  timezone: string,
): Result<DocumentDate, string> {
  const instant = publicationInstant(date, timezone);
  if (!instant.ok) return instant;
  // The first ten characters are the date in the document's own offset, which
  // is what a reader sees; converting the instant would shift it for some.
  return ok({ instant: instant.value, isoDate: date.slice(0, 10) });
}

function midnightIn(
  timezone: string,
  year: number,
  month: number,
  day: number,
): Result<Date, string> {
  if (!isCalendarDate(year, month, day)) {
    return err(`${year}-${pad(month)}-${pad(day)} is not a calendar date.`);
  }
  const wallClock = new Date(Date.UTC(year, month - 1, day));

  // The timezone's offset depends on the instant we are looking for, so
  // measure it at the wall clock read as UTC, then once more at that first
  // estimate. The first reading can fall on the wrong side of a daylight
  // saving change by up to the offset itself; the second cannot, except in
  // the hour a change skips or repeats.
  const before = offsetAt(wallClock, timezone);
  const after = offsetAt(new Date(wallClock.getTime() - before), timezone);
  const midnight = wallClock.getTime() - after;

  // Midnight fell in a gap if the answer reads as the evening before. The day
  // then begins at the change itself: the wall clock read with the offset in
  // force before it, which is the smaller one as clocks move forward. A day
  // the zone skipped entirely (Pacific/Apia on 2011-12-30) thus resolves to
  // the next day's midnight.
  const inGap =
    midnight + offsetAt(new Date(midnight), timezone) < wallClock.getTime();
  return ok(
    new Date(inGap ? wallClock.getTime() - Math.min(before, after) : midnight),
  );
}

/** Whether the day exists, which `Date.UTC` would not say: it rolls overflow into the next month. */
function isCalendarDate(year: number, month: number, day: number): boolean {
  const date = new Date(Date.UTC(year, month - 1, day));
  return (
    date.getUTCFullYear() === year &&
    date.getUTCMonth() === month - 1 &&
    date.getUTCDate() === day
  );
}

/** The timezone's offset from UTC at `instant`, in milliseconds. */
function offsetAt(instant: Date, timezone: string): number {
  const parts = new Intl.DateTimeFormat("en", {
    timeZone: timezone,
    timeZoneName: "longOffset",
  }).formatToParts(instant);
  const name = parts.find((part) => part.type === "timeZoneName")?.value ?? "";
  // "GMT" alone means UTC; otherwise "GMT+01:00" or "GMT-03:30".
  const match = /^GMT(?:([+−-])(\d{2}):(\d{2}))?$/.exec(name);
  // `parseConfig` has already validated the timezone, so a name we cannot
  // read is a bug here, not bad input.
  if (match === null) {
    throw new Error(`Cannot read the offset of ${timezone} from "${name}".`);
  }
  const [, sign, hours, minutes] = match;
  if (sign === undefined) return 0;
  const offset = (Number(hours) * 60 + Number(minutes)) * MINUTE;
  return sign === "+" ? offset : -offset;
}

function pad(value: number): string {
  return String(value).padStart(2, "0");
}
