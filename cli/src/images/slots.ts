/** Runs a task once one of the limiter's slots is free. */
export type WithSlot = <T>(work: () => Promise<T>) => Promise<T>;

/** Runs at most `slots` tasks at once; the others wait their turn in order. */
export function slotLimiter(slots: number): WithSlot {
  let busy = 0;
  const waiting: (() => void)[] = [];
  return async (work) => {
    if (busy < slots) {
      busy++;
    } else {
      // A finishing task hands its slot straight to the next one waiting.
      await new Promise<void>((resolve) => waiting.push(resolve));
    }
    try {
      return await work();
    } finally {
      const next = waiting.shift();
      if (next === undefined) busy--;
      else next();
    }
  };
}
