import { describe, expect, it } from "vitest";
import { data } from "./data";
import { dueItems, lessonStarted, outcomeOf, settleCheck } from "./lessonLogic";
import type { WebState } from "./storage";

// The same scripted session as the Julia test "lessons: hint before reveal, BKT
// and SM-2 state": lesson L01, check 1 wrong (b) then right (a); check 2 right
// (c); check 3 wrong twice (b, c); on 2026-11-08.
describe("settleCheck (port of Lessons.run_lesson scoring)", () => {
  const lesson = data.lessons[0];
  const today = "2026-11-08";
  const letters = { a: 1, b: 2, c: 3, d: 4 } as const;

  it("matches the Julia scripted session", () => {
    let s: WebState = { kc: {}, items: {}, misconceptions: {} };
    const [c1, c2, c3] = lesson.checks;
    expect(lesson.id).toBe("L01-dispatch");
    s = settleCheck(s, lesson, c1, letters.b, letters.a, today);
    s = settleCheck(s, lesson, c2, letters.c, null, today);
    s = settleCheck(s, lesson, c3, letters.b, letters.c, today);
    expect([outcomeOf(c1, 2, 1), outcomeOf(c2, 3, null), outcomeOf(c3, 2, 3)]).toEqual([
      "second-try", "first-try", "revealed",
    ]);
    expect(s.misconceptions["first-match-wins"]).toBe(1);
    expect(s.items["L01-dispatch/specificity"].repetitions).toBe(1);   // quality 3
    expect(s.items["L01-dispatch/runtime-types"].repetitions).toBe(0); // quality 1
    expect(s.items["L01-dispatch/runtime-types"].due).toBe("2026-11-09");
    expect(s.kc["multiple-dispatch"]).toBeGreaterThan(0);
    expect(s.kc["multiple-dispatch"]).toBeLessThan(1);
    expect(lessonStarted(s, "L01-dispatch")).toBe(true);
    expect(lessonStarted(s, "L02-concrete-types")).toBe(false);
    expect(dueItems(s, "2026-11-09")).toContain("L01-dispatch/runtime-types");
  });

  it("never mutates the previous state", () => {
    const s0: WebState = { kc: {}, items: {}, misconceptions: {} };
    settleCheck(s0, lesson, lesson.checks[0], 2, 1, today);
    expect(s0).toEqual({ kc: {}, items: {}, misconceptions: {} });
  });

  it("has a misconception for every wrong option of every check (site data invariant)", () => {
    for (const l of data.lessons) {
      for (const c of l.checks) {
        const wrong = c.options.map((_, i) => i + 1).filter((i) => i !== c.answer);
        expect(wrong.every((i) => c.misconceptions.some((m) => m.option === i))).toBe(true);
        expect(l.verified_on).toBe(data.julia);
      }
    }
  });
});
