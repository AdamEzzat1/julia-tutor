import { describe, expect, it } from "vitest";
import { course } from "./course";
import type { Progress } from "./progress";
import { addMiss, dueCards, missedKeys, nextDue, resolve, seed, settleReview, type Reviews } from "./review";

const progress = (over: Partial<Progress>): Progress => ({
  solved: {}, opened: {}, questions: {}, predictions: {}, choices: {}, breaks: {}, bugs: {}, parsons: {}, ladder: {},
  races: {}, explores: {}, ...over,
});

// Real keys from the site data: the first question, first choice prediction and first typed prediction.
const units = course.units;
const firstQ = (() => {
  for (const u of units) for (const [i, s] of u.sections.entries()) for (const [k, q] of s.questions.entries())
    if (q.kind !== "error") return `${u.id}/${i}/${k}`;
  throw new Error("no question");
})();
const firstPred = (typed: boolean) => {
  for (const u of units) for (const [i, s] of u.sections.entries()) for (const [e, ex] of s.examples.entries())
    if (ex.predict && !!ex.predict.typed === typed) return `${u.id}/${i}/${e}`;
  throw new Error("no prediction");
};

describe("reviews due (SM-2 from missed questions)", () => {
  it("queues missed questions and missed predictions, not first-try answers, hits or skipped predictions", () => {
    const p = progress({
      questions: { "a/0/0": "first-try", "a/0/1": "later" },
      predictions: { "a/1/0": { pick: 2, hit: false }, "a/1/1": { pick: 1, hit: true }, "a/1/2": { pick: 0, hit: false },
                     "a/1/3": { pick: 1, hit: false, value: 7 } },
    });
    expect(missedKeys(p)).toEqual(["p:a/1/0", "p:a/1/3", "q:a/0/1"]);
  });

  it("a live miss is a lapse due tomorrow; a miss found in saved progress is due today; neither is queued twice", () => {
    const live = addMiss({}, "q:a/0/1", "2026-11-16");
    expect(live["q:a/0/1"]).toMatchObject({ repetitions: 0, intervalDays: 1, due: "2026-11-17", reviews: 0 });
    expect(live["q:a/0/1"].easiness).toBeCloseTo(2.18, 12); // 2.5 + 0.1 − 3·(0.08 + 3·0.02)
    expect(addMiss(live, "q:a/0/1", "2026-11-20")).toBe(live);
    const seeded = seed(live, progress({ questions: { "a/0/1": "later", "a/0/2": "later" } }), "2026-11-16");
    expect(seeded["q:a/0/1"].due).toBe("2026-11-17"); // kept
    expect(seeded["q:a/0/2"].due).toBe("2026-11-16"); // date unknown: due now
    const none: Reviews = {};
    expect(seed(none, progress({}), "2026-11-16")).toBe(none);
  });

  it("schedules reviews with the course's SM-2: 1, 6, then interval × easiness; a miss resets to 1 day", () => {
    let r = addMiss({}, "k", "2026-11-01");
    r = settleReview(r, "k", true, "2026-11-02");
    expect(r.k).toMatchObject({ repetitions: 1, intervalDays: 1, due: "2026-11-03", reviews: 1 });
    expect(r.k.easiness).toBeCloseTo(2.28, 12);
    r = settleReview(r, "k", true, "2026-11-03");
    expect(r.k).toMatchObject({ repetitions: 2, intervalDays: 6, due: "2026-11-09" });
    r = settleReview(r, "k", true, "2026-11-09");
    expect(r.k).toMatchObject({ repetitions: 3, intervalDays: 14, due: "2026-11-23" }); // round(6 × 2.38)
    r = settleReview(r, "k", false, "2026-11-23");
    expect(r.k).toMatchObject({ repetitions: 0, intervalDays: 1, due: "2026-11-24", reviews: 4 });
    expect(r.k.easiness).toBeCloseTo(2.16, 12); // 2.48 − 0.32
  });

  it("resolves review keys against the site data: questions, choice and typed predictions", () => {
    const q = resolve(`q:${firstQ}`, units);
    expect(q?.kind).toBe("question");
    const c = resolve(`p:${firstPred(false)}`, units);
    expect(c?.kind === "prediction" && !c.p.typed && c.p.answer >= 1).toBe(true);
    const t = resolve(`p:${firstPred(true)}`, units);
    expect(t?.kind === "prediction" && t.p.typed !== undefined).toBe(true);
    expect(resolve("q:no-such-unit/0/0", units)).toBeNull();
    expect(resolve(`q:${firstQ.split("/")[0]}/0/999`, units)).toBeNull();
    expect(resolve(`p:${firstQ.split("/")[0]}/0/999`, units)).toBeNull();
    expect(resolve("x:garbage", units)).toBeNull();
  });

  it("lists due cards earliest first, leaves out other courses' items and reports stale ones", () => {
    const u0 = firstQ.split("/")[0];
    const other = units.find((u) => u.course !== units.find((x) => x.id === u0)!.course)!;
    const mine = units.filter((u) => u.course === units.find((x) => x.id === u0)!.course);
    const r: Reviews = {
      [`q:${firstQ}`]: { repetitions: 0, intervalDays: 1, easiness: 2.18, due: "2026-11-15", reviews: 0 },
      [`q:${u0}/0/999`]: { repetitions: 0, intervalDays: 1, easiness: 2.18, due: "2026-11-10", reviews: 0 },
      [`q:${other.id}/0/0`]: { repetitions: 0, intervalDays: 1, easiness: 2.18, due: "2026-11-10", reviews: 0 },
      [`q:${u0}/0/0x`]: { repetitions: 0, intervalDays: 1, easiness: 2.18, due: "2026-11-30", reviews: 0 },
    };
    const { cards, stale } = dueCards(r, mine, "2026-11-16");
    expect(cards.map((c) => c.key)).toEqual([`q:${firstQ}`]);
    expect(stale).toEqual([`q:${u0}/0/999`]);
    expect(nextDue(r, "2026-11-16")).toBe("2026-11-30");
    expect(nextDue(r, "2026-12-01")).toBeNull();
    // scoped to a course: the other course's item (due 11-10) never counts
    expect(nextDue(r, "2026-11-01", [other])).toBe("2026-11-10");
    expect(nextDue(r, "2026-11-12", [other])).toBeNull();
    expect(nextDue(r, "2026-11-12", mine)).toBe("2026-11-15");
  });
});
