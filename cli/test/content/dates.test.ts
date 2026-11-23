import { describe, expect, test } from "bun:test";
import { publicationDate, publicationInstant } from "../../src/content/dates";

function instant(date: string, timezone: string): string {
  const result = publicationInstant(date, timezone);
  if (!result.ok) throw new Error(result.error);
  return result.value.toISOString();
}

describe("publicationInstant", () => {
  test("puts a date-only value at midnight in the timezone", () => {
    expect(instant("2026-11-30", "UTC")).toBe("2026-11-30T00:00:00.000Z");
    expect(instant("2026-07-01", "Europe/Lisbon")).toBe(
      "2026-06-30T23:00:00.000Z",
    );
    expect(instant("2026-01-15", "Europe/Lisbon")).toBe(
      "2026-01-15T00:00:00.000Z",
    );
    expect(instant("2026-11-30", "America/Sao_Paulo")).toBe(
      "2026-11-30T03:00:00.000Z",
    );
    expect(instant("2026-11-30", "Asia/Kolkata")).toBe(
      "2026-11-29T18:30:00.000Z",
    );
  });

  test("handles midnight on the day daylight saving time begins", () => {
    // Lisbon moves from +00:00 to +01:00 at 01:00 on 2026-03-29.
    expect(instant("2026-03-29", "Europe/Lisbon")).toBe(
      "2026-03-29T00:00:00.000Z",
    );
    expect(instant("2026-03-30", "Europe/Lisbon")).toBe(
      "2026-03-29T23:00:00.000Z",
    );
  });

  test("takes a full timestamp with an offset as given", () => {
    expect(instant("2026-11-30T10:00:00+02:00", "UTC")).toBe(
      "2026-11-30T08:00:00.000Z",
    );
    expect(instant("2026-11-30T10:00:00Z", "Europe/Lisbon")).toBe(
      "2026-11-30T10:00:00.000Z",
    );
  });

  test("rejects dates that do not exist or are not dates", () => {
    for (const bad of [
      "2026-13-01",
      "2026-02-30",
      "yesterday",
      "2026-11-30T10:00:00",
      "2026-11-30T25:00:00Z",
      "2026-02-30T10:00:00Z",
      "2026-11-30T24:00:00Z",
      "2026-11-30T10:60:00Z",
      "2026-11-30T10:00:60Z",
    ]) {
      expect(publicationInstant(bad, "UTC").ok).toBe(false);
    }
  });
});

describe("publicationDate", () => {
  test("keeps the calendar date as written, in the document's own offset", () => {
    const date = publicationDate("2026-11-30T23:30:00-05:00", "UTC");

    expect(date).toEqual({
      ok: true,
      value: {
        instant: new Date("2026-12-01T04:30:00.000Z"),
        isoDate: "2026-11-30",
      },
    });
  });
});
