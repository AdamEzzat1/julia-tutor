// The question formats added after Phase 5: typed-number predictions, races,
// explorer questions and error questions (course/AUTHORING.md). The keys are
// measured by `tutor course verify`; these tests check that the browser scores
// a pick the way the key says, and that the exported data carries what each
// component needs.
import { describe, expect, it } from "vitest";
import { course, type Explorer, type Prediction, type Race } from "./course";
import { parseTyped, settleTyped, toleranceText, withinTolerance } from "./predict";
import { raceText, settleRace, unitRaceKeys } from "./race";
import { exploreVerdict, pointText, settleExplore } from "./explore";

const examples = course.units.flatMap((u) => u.sections.flatMap((s) => s.examples.map((ex) => ({ unit: u.id, ex }))));

describe("typed-number predictions", () => {
  const T = (within: "abs" | "rel" | "factor", tolerance: number, value: number): Prediction =>
    ({ kc: "k", prompt: "p", choices: [], answer: 0, explain: "e", measured: String(value),
       typed: { tolerance, within, unit: "digits", value } });

  it("reads numbers the way a learner writes them, and nothing else", () => {
    expect(parseTyped("4")).toBe(4);
    expect(parseTyped(" -2.5 ")).toBe(-2.5);
    expect(parseTyped("1e-6")).toBe(1e-6);
    expect(parseTyped("+3")).toBe(3);
    expect(parseTyped(".5")).toBe(0.5);
    for (const bad of ["", "four", "1/2", "1e", "Inf", "NaN", "0x10", "1,5"]) expect(parseTyped(bad)).toBeNull();
  });

  it("scores against the tolerance, as Course.within_tolerance does", () => {
    expect(withinTolerance(T("abs", 0.5, 4).typed!, 4.5)).toBe(true);     // the edge is inside
    expect(withinTolerance(T("abs", 0.5, 4).typed!, 4.51)).toBe(false);
    expect(withinTolerance(T("rel", 0.1, 200).typed!, 181)).toBe(true);
    expect(withinTolerance(T("rel", 0.1, 200).typed!, 179)).toBe(false);
    expect(withinTolerance(T("factor", 2, 1e-6).typed!, 4e-7)).toBe(false);
    expect(withinTolerance(T("factor", 2, 1e-6).typed!, 5e-7)).toBe(true);
    expect(withinTolerance(T("factor", 2, 1e-6).typed!, 2e-6)).toBe(true);
    expect(withinTolerance(T("factor", 2, 1e-6).typed!, -1e-6)).toBe(false);  // a factor needs the same sign
  });

  it("a skip is pick 0, never a hit; a commit keeps the number typed", () => {
    expect(settleTyped(T("abs", 1, 7), null)).toEqual({ pick: 0, hit: false });
    expect(settleTyped(T("abs", 1, 7), 6)).toEqual({ pick: 1, hit: true, value: 6 });
    expect(settleTyped(T("abs", 1, 7), 5)).toEqual({ pick: 1, hit: false, value: 5 });
  });

  it("says the tolerance in words", () => {
    expect(toleranceText(T("abs", 1, 7).typed!)).toBe("within 1 digits");
    expect(toleranceText(T("rel", 0.1, 7).typed!)).toBe("within 10%");
    expect(toleranceText(T("factor", 2, 7).typed!)).toBe("within a factor of 2");
  });

  it("the site data's typed predictions hold their measured value", () => {
    for (const { ex } of examples) {
      const t = ex.predict?.typed;
      if (!t) continue;
      expect(ex.predict!.choices).toEqual([]);
      expect(Number(ex.predict!.measured)).toBe(t.value);
      expect(withinTolerance(t, t.value)).toBe(true);
      expect(t.tolerance).toBeGreaterThan(0);
    }
  });
});

describe("races", () => {
  const R: Race = { kc: "k", prompt: "p", choices: ["`a`: loop", "`b`: broadcast", "`c`: comprehension"], by: "bytes",
                    unit: "bytes", margin: 2, answer: 1, explain: "e", misconceptions: ["", "m2", "m3"],
                    measured: ["0", "80048", "80048"], ratios: [1, null, null] };

  it("scores one pick; 0 is a skip", () => {
    expect(settleRace(R, 1)).toEqual({ pick: 1, hit: true });
    expect(settleRace(R, 2)).toEqual({ pick: 2, hit: false });
    expect(settleRace(R, 0)).toEqual({ pick: 0, hit: false });
  });

  it("writes the measured table against the winner", () => {
    expect(raceText(R, 0)).toBe("0 bytes (the winner)");
    expect(raceText(R, 1)).toBe("80048 bytes (the winner allocates nothing)");
    const T: Race = { ...R, by: "time", unit: "μs", measured: ["4.1", "95"], ratios: [1, 23.2], choices: ["a", "b"] };
    expect(raceText(T, 1)).toBe("95 μs (23.2× the winner)");
  });

  it("every exported race: the winner beats every other choice by the margin", () => {
    for (const { ex } of examples) {
      const r = ex.race;
      if (!r) continue;
      expect(r.measured.length).toBe(r.choices.length);
      r.ratios.forEach((x, i) => { if (i !== r.answer - 1) expect(x === null || x >= r.margin).toBe(true); });
      expect(r.misconceptions[r.answer - 1]).toBe("");
    }
    for (const u of course.units) expect(unitRaceKeys(u).every((k) => k.startsWith(u.id + "/"))).toBe(true);
  });
});

describe("explorer questions", () => {
  // A 2 x 4 grid: method (words) x h (numbers); the question asks for the largest h where err < 1e-4 at method B.
  const X: Explorer = {
    kc: "k", prompt: "p", x: "h", series: "method", label: "error", log: true, explain: "e",
    axes: [{ group: "method", label: "method", log: false, numeric: false, texts: ["A", "B"], nums: [] },
           { group: "h", label: "h", log: true, numeric: true, texts: ["0.1", "0.2", "0.4", "0.8"], nums: [0.1, 0.2, 0.4, 0.8] }],
    values: ["1e-3", "2e-3", "4e-3", "8e-3", "1e-6", "1e-5", "1e-3", "1e-2"],
    question: { prompt: "q", along: "h", pick: "largest", holds: "below", limit: 1e-4, explain: "e",
                answer: [1, 1], holdsAt: [true, true, false, false] },
  };

  it("names what is wrong with a committed point", () => {
    expect(exploreVerdict(X, [1, 1])).toBe("right");
    expect(exploreVerdict(X, [1, 0])).toBe("short");      // holds, but a larger h still does
    expect(exploreVerdict(X, [1, 2])).toBe("fails");      // past the edge
    expect(exploreVerdict(X, [0, 1])).toBe("elsewhere");  // the other slider is not where the question puts it
    expect(settleExplore(X, null)).toEqual({ point: null, verdict: "skipped" });
    expect(settleExplore(X, [1, 1])).toEqual({ point: [1, 1], verdict: "right" });
    expect(pointText(X, [1, 1])).toBe("method: B · h: 0.2");
  });

  it("every explorer in the site data asks a question, and its key agrees with the grid", () => {
    const xs = examples.filter((e) => e.ex.explore).map((e) => e.ex.explore!);
    expect(xs.length).toBeGreaterThanOrEqual(3);
    for (const x of xs) {
      const q = x.question!;
      expect(q).toBeDefined();
      const ai = x.axes.findIndex((a) => a.group === q.along);
      expect(q.holdsAt.length).toBe(x.axes[ai].texts.length);
      expect(q.holdsAt[q.answer[ai]]).toBe(true);
      // the answer is the extreme value where the condition holds, and it does not hold everywhere
      const held = q.holdsAt.flatMap((h, j) => (h ? [j] : []));
      expect(q.answer[ai]).toBe(q.pick === "largest" ? held[held.length - 1] : held[0]);
      expect(q.holdsAt.some((h) => !h)).toBe(true);
      expect(exploreVerdict(x, q.answer)).toBe("right");
    }
  });
});

describe("error questions", () => {
  it("each carries the message Julia printed, and the message names an error or a warning", () => {
    for (const u of course.units)
      for (const s of u.sections)
        for (const q of s.questions) {
          if (q.kind !== "error") continue;
          expect(q.output).toBeTruthy();
          expect(/^ERROR: |Warning:/m.test(q.output!)).toBe(true);
          expect(q.misconceptions[q.answer - 1]).toBe("");
        }
  });
});
