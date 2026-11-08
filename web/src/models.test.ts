import { describe, expect, it } from "vitest";
import {
  addDays, bktParams, bktUpdate, ochiai, rankByOchiai, roundHalfEven, sm2Due, sm2Initial, sm2Update,
} from "./models";
import { data } from "./data";

// Same hand-computed values as the "models" testset in test/runtests.jl.
const close = (a: number, b: number, rtol = 1e-12) => Math.abs(a - b) <= rtol * Math.abs(b);

describe("BKT (port of Models.bkt_update)", () => {
  const θ = bktParams();
  it("matches the hand-computed posteriors", () => {
    expect(close(bktUpdate(0.2, true, θ), 0.18 / 0.38 + (1 - 0.18 / 0.38) * 0.15)).toBe(true);
    expect(close(bktUpdate(0.2, true, θ), 0.5526315789473684)).toBe(true);
    expect(close(bktUpdate(0.2, false, θ), 0.02 / 0.62 + (1 - 0.02 / 0.62) * 0.15)).toBe(true);
    expect(bktUpdate(0.5, true, θ)).toBeGreaterThan(0.5);
    expect(bktUpdate(0.5, false, θ)).toBeLessThan(0.5);
  });
  it("rejects guess + slip >= 1", () => {
    expect(() => bktParams({ pInit: 0.2, pLearn: 0.1, pGuess: 0.6, pSlip: 0.5 })).toThrow(RangeError);
  });
});

describe("SM-2 (port of Models.sm2_update)", () => {
  it("schedules 1, 6, 16 days and lapses to 1", () => {
    const s1 = sm2Update(sm2Initial(), 5);
    const s2 = sm2Update(s1, 5);
    const s3 = sm2Update(s2, 5);
    expect([s1.repetitions, s1.intervalDays, s2.intervalDays, s3.intervalDays]).toEqual([1, 1, 6, 16]);
    expect(close(s3.easiness, 2.8)).toBe(true);
    const lapse = sm2Update(s3, 1);
    expect([lapse.repetitions, lapse.intervalDays]).toEqual([0, 1]);
    expect(close(sm2Update(sm2Initial(), 2).easiness, 2.18)).toBe(true);
    expect(sm2Update({ repetitions: 0, intervalDays: 0, easiness: 1.3 }, 0).easiness).toBeGreaterThanOrEqual(1.3);
    expect(sm2Due(s2, "2026-11-08")).toBe("2026-11-14");
  });
  it("rounds half to even like Julia's round(Int, x)", () => {
    expect([roundHalfEven(2.5), roundHalfEven(3.5), roundHalfEven(15.6), roundHalfEven(15.4)]).toEqual([2, 4, 16, 15]);
  });
  it("adds days across month and year ends in UTC", () => {
    expect(addDays("2026-12-30", 3)).toBe("2027-01-02");
    expect(addDays("2028-02-28", 1)).toBe("2028-02-29");
  });
});

describe("Ochiai (port of Models.ochiai / rank_by_ochiai)", () => {
  it("matches the Julia cases", () => {
    expect(ochiai(2, 0, 2)).toBe(1);
    expect(close(ochiai(1, 1, 2), 0.5, 1e-15)).toBe(true);
    expect(ochiai(0, 3, 1)).toBe(0);
    expect(ochiai(0, 0, 0)).toBe(0);
    const r = rankByOchiai({ a: ["t1", "t2"], b: ["t1"], c: ["t3"] }, new Set(["t1"]), ["a", "b", "c"]);
    expect(r.map((x) => x.hole)).toEqual(["b", "a", "c"]);
    const tie = rankByOchiai({ a: ["t1"], b: ["t1"] }, new Set(["t1"]), ["b", "a"]);
    expect(tie.map((x) => x.hole)).toEqual(["b", "a"]);
  });

  // Cross-language check: for every explain fixture, the ranking this port
  // computes from the exported hole map equals the one Julia printed in the
  // golden output (same failing testsets, same stage holes).
  const project = data.projects[0];
  for (const f of project.fixtures.filter((x) => x.expect_start !== "JT000")) {
    it(`reproduces the Julia ranking in golden ${f.name}`, () => {
      const lines = f.golden.split("\n");
      const failing = new Set(
        lines.filter((l) => l.trimStart().startsWith("FAIL ")).map((l) => l.trim().slice(5).split("  [")[0]),
      );
      const stageHoles = project.holes.filter((h) => h.stage <= f.stage).map((h) => h.id);
      const ours = rankByOchiai(project.deps, failing, stageHoles).map(
        (r) => `${r.hole} ${juliaRound2(r.score)} ${r.failedDep} ${r.passedDep}`,
      );
      const theirs = lines
        .filter((l) => /^\s+\d+\. \S+\s+\S+\s+(implemented|not started)/.test(l))
        .map((l) => {
          const m = l.match(/^\s+\d+\. (\S+)\s+(\S+)\s+.*failing-deps=(\d+) passing-deps=(\d+)/)!;
          return `${m[1]} ${m[2]} ${m[3]} ${m[4]}`;
        });
      expect(ours).toEqual(theirs);
    });
  }
});

/** Julia prints round(x; digits = 2) as e.g. "0.71", "1.0", "0.0". */
function juliaRound2(x: number): string {
  const r = Math.round(x * 100) / 100;
  return Number.isInteger(r) ? r.toFixed(1) : String(r);
}
