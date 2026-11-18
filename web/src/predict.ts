// Predict, then run (Phase 5): an example with a prediction hides its recorded
// output until the learner commits one choice. The key is not typed by an
// author: `tutor course verify` reads it from the recorded output (src/course.jl,
// `prediction_key_problems`), and `tutor site-data` exports a prediction only
// when its key holds.
//
// One pick, no retries: a prediction is scored once, so the hit rate per
// knowledge component means "right before seeing the result". Showing the
// output without predicting is allowed and recorded as pick 0, which the
// rates leave out.
import type { Prediction, Typed, Unit } from "./course";

export interface PredictionRecord {
  /** 1-based choice (1 for a committed typed number); 0 = the output was shown without a prediction */
  pick: number;
  hit: boolean;
  /** a typed-number prediction: the number committed */
  value?: number;
}

export const predictionKey = (unit: string, section: number, example: number) => `${unit}/${section}/${example}`;

export function settlePrediction(p: Prediction, pick: number): PredictionRecord {
  return { pick, hit: pick > 0 && pick === p.answer };
}

/**
 * A typed-number prediction (`p.typed`): the hit test mirrors
 * `Course.within_tolerance` in src/course.jl.
 */
export function withinTolerance(t: Typed, x: number): boolean {
  if (!Number.isFinite(x)) return false;
  if (t.within === "rel") return Math.abs(x - t.value) <= t.tolerance * Math.abs(t.value);
  if (t.within === "factor") return x > 0 && t.value > 0 && t.value / t.tolerance <= x && x <= t.value * t.tolerance;
  return Math.abs(x - t.value) <= t.tolerance;
}

/** A typed number, as a learner writes it ("4", "-2.5", "1e-6", "1.5e3"); null if it is not one. */
export function parseTyped(s: string): number | null {
  const t = s.trim().replace(/^\+/, "");
  if (!/^-?(\d+\.?\d*|\.\d+)([eE][-+]?\d+)?$/.test(t)) return null;
  const x = Number(t);
  return Number.isFinite(x) ? x : null;
}

/** Commit a typed number (null: shown without predicting, pick 0). */
export function settleTyped(p: Prediction, x: number | null): PredictionRecord {
  if (x === null) return { pick: 0, hit: false };
  return { pick: 1, hit: withinTolerance(p.typed!, x), value: x };
}

/** The tolerance as the learner reads it: "within 0.5", "within 10%", "within a factor of 2". */
export function toleranceText(t: Typed): string {
  if (t.within === "rel") return `within ${+(t.tolerance * 100).toPrecision(3)}%`;
  if (t.within === "factor") return `within a factor of ${t.tolerance}`;
  return `within ${t.tolerance}${t.unit ? ` ${t.unit}` : ""}`;
}

export interface KcRate {
  kc: string;
  hits: number;
  total: number;
}

/**
 * Hits per knowledge component, over the predictions in `units` that have a
 * committed pick. A record whose example no longer has a prediction (the
 * course changed) is not counted; a skipped one (pick 0) is not a prediction.
 */
export function predictionRates(records: Record<string, PredictionRecord>, units: Unit[]): KcRate[] {
  const by = new Map<string, KcRate>();
  for (const u of units)
    u.sections.forEach((s, i) =>
      s.examples.forEach((e, j) => {
        const r = records[predictionKey(u.id, i, j)];
        if (!e.predict || !r || r.pick === 0) return;
        const k = by.get(e.predict.kc) ?? { kc: e.predict.kc, hits: 0, total: 0 };
        k.total += 1;
        if (r.hit) k.hits += 1;
        by.set(e.predict.kc, k);
      }),
    );
  return [...by.values()].sort((a, b) => a.kc.localeCompare(b.kc));
}

/** Every prediction key of a unit, in page order. */
export const unitPredictionKeys = (u: Unit) =>
  u.sections.flatMap((s, i) => s.examples.flatMap((e, j) => (e.predict ? [predictionKey(u.id, i, j)] : [])));
