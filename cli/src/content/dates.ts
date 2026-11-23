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
    const [, year, month, day] = dateOnly.map(Number);
    return midnightIn(timezone, year as number, month as number, day as number);
  }
  const timestamp = TIMESTAMP_WITH_OFFSET.exec(date);
  if (timestamp) {
    // `new Date` rolls impossible values over (February 30th becomes March
    // 2nd, 24:00 the next day), so the parts are checked first.
    const [, year, month, day, hour, minute, second] = timestamp.map(Number);
    const instant = new Date(date);
    if (
      isCalendarDate(year as number, month as number, day as number) &&
      (hour as number) <= 23 &&
      (minute as number) <= 59 &&
      (second ?? 0) <= 59 &&
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
  // the hour a change skips or repeats, where any answer is a guess.
  const estimate = wallClock.getTime() - offsetAt(wallClock, timezone);
  return ok(
    new Date(wallClock.getTime() - offsetAt(new Date(estimate), timezone)),
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
  const [, sign, hours, minutes] =
    /^GMT(?:([+−-])(\d{2}):(\d{2}))?$/.exec(name) ?? [];
  if (sign === undefined) return 0;
  const offset = (Number(hours) * 60 + Number(minutes)) * MINUTE;
  return sign === "+" ? offset : -offset;
}

function pad(value: number): string {
  return String(value).padStart(2, "0");
}
