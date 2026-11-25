import { describe, expect, test } from "bun:test";
import { slotLimiter } from "../../src/images/slots";

describe("slotLimiter", () => {
  test("never runs more tasks at once than it has slots", async () => {
    const withSlot = slotLimiter(3);
    let running = 0;
    let most = 0;
    const task = async (index: number) => {
      running++;
      most = Math.max(most, running);
      await Bun.sleep(index % 4);
      running--;
      return index;
    };

    const results = await Promise.all(
      Array.from({ length: 50 }, (_, index) => withSlot(() => task(index))),
    );

    expect(most).toBe(3);
    expect(results).toEqual(Array.from({ length: 50 }, (_, index) => index));
  });

  test("frees the slot of a task that throws", async () => {
    const withSlot = slotLimiter(1);

    const failed = withSlot(() => Promise.reject(new Error("broken")));

    await expect(failed).rejects.toThrow("broken");
    expect(await withSlot(async () => "next")).toBe("next");
  });
});
