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
import type { Prediction, Unit } from "./course";

export interface PredictionRecord {
  /** 1-based choice; 0 = the output was shown without a prediction */
  pick: number;
  hit: boolean;
}

export const predictionKey = (unit: string, section: number, example: number) => `${unit}/${section}/${example}`;

export function settlePrediction(p: Prediction, pick: number): PredictionRecord {
  return { pick, hit: pick > 0 && pick === p.answer };
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
