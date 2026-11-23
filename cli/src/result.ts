/** The outcome of an operation whose failure is expected, so it is returned instead of thrown. */
export type Result<T, E> = { ok: true; value: T } | { ok: false; error: E };

export function ok<T>(value: T): Result<T, never> {
  return { ok: true, value };
}

export function err<E>(error: E): Result<never, E> {
  return { ok: false, error };
}

/**
 * Turns many results into one, keeping every error rather than stopping at
 * the first, so a stage can report all its problems in a single run.
 */
export function collect<T, E>(results: Result<T, E[]>[]): Result<T[], E[]> {
  const values: T[] = [];
  const errors: E[] = [];
  for (const result of results) {
    if (result.ok) {
      values.push(result.value);
    } else {
      errors.push(...result.error);
    }
  }
  return errors.length > 0 ? err(errors) : ok(values);
}
