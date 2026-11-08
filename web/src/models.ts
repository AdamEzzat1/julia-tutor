// Ports of src/models.jl (BKT, SM-2, Ochiai). These must agree with the Julia
// versions number for number: models.test.ts uses the same hand-computed values
// as the Julia test suite ("models" testset in test/runtests.jl).

export interface BKTParams {
  pInit: number;
  pLearn: number;
  pGuess: number;
  pSlip: number;
}

export function bktParams(p: Partial<BKTParams> = {}): BKTParams {
  const θ = { pInit: 0.2, pLearn: 0.15, pGuess: 0.25, pSlip: 0.1, ...p };
  for (const [k, v] of Object.entries(θ)) {
    if (!(v >= 0 && v <= 1)) throw new RangeError(`${k} must be in [0, 1], got ${v}`);
  }
  if (!(θ.pGuess + θ.pSlip < 1)) {
    throw new RangeError("pGuess + pSlip must be < 1 (else a correct answer is evidence of not knowing)");
  }
  return θ;
}

/** Posterior P(known) after one observation, then the learning transition. */
export function bktUpdate(pKnown: number, correct: boolean, θ: BKTParams): number {
  let num: number, den: number;
  if (correct) {
    num = pKnown * (1 - θ.pSlip);
    den = num + (1 - pKnown) * θ.pGuess;
  } else {
    num = pKnown * θ.pSlip;
    den = num + (1 - pKnown) * (1 - θ.pGuess);
  }
  const posterior = num / den;
  return posterior + (1 - posterior) * θ.pLearn;
}

export interface SM2State {
  repetitions: number;
  intervalDays: number;
  easiness: number;
}

export const sm2Initial = (): SM2State => ({ repetitions: 0, intervalDays: 0, easiness: 2.5 });

/** quality in 0..5. Here: 5 = right first try, 3 = right after the hint, 1 = revealed. */
export function sm2Update(s: SM2State, quality: number): SM2State {
  if (!Number.isInteger(quality) || quality < 0 || quality > 5) {
    throw new RangeError(`quality must be in 0:5, got ${quality}`);
  }
  const q = quality;
  const ef = Math.max(1.3, s.easiness + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02)));
  if (q < 3) return { repetitions: 0, intervalDays: 1, easiness: ef };
  const reps = s.repetitions + 1;
  // Julia's round(Int, x) rounds half to even; Math.round rounds half up.
  const interval = reps === 1 ? 1 : reps === 2 ? 6 : roundHalfEven(s.intervalDays * s.easiness);
  return { repetitions: reps, intervalDays: interval, easiness: ef };
}

export function roundHalfEven(x: number): number {
  const f = Math.floor(x);
  const d = x - f;
  if (d > 0.5) return f + 1;
  if (d < 0.5) return f;
  return f % 2 === 0 ? f : f + 1;
}

/** ISO date (YYYY-MM-DD) plus n days, computed in UTC so time zones cannot shift it. */
export function addDays(iso: string, n: number): string {
  const [y, m, d] = iso.split("-").map(Number);
  const t = Date.UTC(y, m - 1, d) + n * 86_400_000;
  return new Date(t).toISOString().slice(0, 10);
}

export const sm2Due = (s: SM2State, reviewed: string): string => addDays(reviewed, s.intervalDays);

export function ochiai(failedDep: number, passedDep: number, totalFailed: number): number {
  const den = Math.sqrt(totalFailed * (failedDep + passedDep));
  return den === 0 ? 0 : failedDep / den;
}

export interface Ranked {
  hole: string;
  score: number;
  failedDep: number;
  passedDep: number;
}

/** Sorted by score descending, ties by the given (teaching) order, like Julia's rank_by_ochiai. */
export function rankByOchiai(deps: Record<string, string[]>, failing: Set<string>, holes: string[]): Ranked[] {
  const F = failing.size;
  const rows = holes.map((h, i) => {
    const d = deps[h] ?? [];
    const ef = d.filter((t) => failing.has(t)).length;
    return { i, r: { hole: h, score: ochiai(ef, d.length - ef, F), failedDep: ef, passedDep: d.length - ef } };
  });
  rows.sort((a, b) => b.r.score - a.r.score || a.i - b.i);
  return rows.map((x) => x.r);
}
