// Pick the implementation that wins: an example with a race hides its recorded
// measurements (a time or bytes allocated per implementation) until the
// learner picks the one they expect to win. The key is not typed by an author:
// `tutor course verify` re-runs the example and checks that the declared
// winner wins by at least the race's margin (src/course.jl,
// `race_output_problems`), and `tutor site-data` exports only a race that
// passes. Works without `tutor serve`: the numbers are the recorded ones.
// One pick, scored once, like a prediction (predict.ts).
import type { Race, Unit } from "./course";
import { predictionKey } from "./predict";

export interface RaceRecord {
  /** 1-based choice; 0 = the measurements were shown without picking */
  pick: number;
  hit: boolean;
}

export function settleRace(r: Race, pick: number): RaceRecord {
  return { pick, hit: pick > 0 && pick === r.answer };
}

/** "4.1 μs (the winner)", "93 μs (23× the winner)", "160 bytes (the winner allocates nothing)". */
export function raceText(r: Race, i: number): string {
  const v = `${r.measured[i]} ${r.unit}`;
  if (i === r.answer - 1) return `${v} (the winner)`;
  const x = r.ratios[i];
  return x === null ? `${v} (the winner allocates nothing)` : `${v} (${x}× the winner)`;
}

/** Every race key of a unit, in page order (the same `<unit>/<section>/<example>` keys as predictions). */
export const unitRaceKeys = (u: Unit) =>
  u.sections.flatMap((s, i) => s.examples.flatMap((e, j) => (e.race ? [predictionKey(u.id, i, j)] : [])));
