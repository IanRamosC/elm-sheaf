/** The number of single-character edits that turn `a` into `b`. */
function editDistance(a: string, b: string): number {
  let previous = Array.from({ length: b.length + 1 }, (_, index) => index);
  for (let row = 1; row <= a.length; row++) {
    const current = [row];
    for (let column = 1; column <= b.length; column++) {
      const substitution = a[row - 1] === b[column - 1] ? 0 : 1;
      current.push(
        Math.min(
          (previous[column] ?? 0) + 1,
          (current[column - 1] ?? 0) + 1,
          (previous[column - 1] ?? 0) + substitution,
        ),
      );
    }
    previous = current;
  }
  return previous[b.length] ?? 0;
}

/**
 * The candidates that look like a typo of `target`, closest first, for "did
 * you mean" hints. Case is ignored, and a candidate counts as close when it
 * differs by at most a third of the target's length (at least one edit).
 */
export function suggestions(
  target: string,
  candidates: string[],
  limit: number,
): string[] {
  const maxDistance = Math.max(1, Math.ceil(target.length / 3));
  return candidates
    .map((candidate) => ({
      candidate,
      distance: editDistance(target.toLowerCase(), candidate.toLowerCase()),
    }))
    .filter(({ distance }) => distance <= maxDistance)
    .sort((a, b) => a.distance - b.distance)
    .slice(0, limit)
    .map(({ candidate }) => candidate);
}
