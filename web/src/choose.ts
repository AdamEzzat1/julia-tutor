// Method-choice checkpoints (Phase 5): an example with a checkpoint hides its
// recorded work-precision output until the learner picks a method and writes a
// one-line reason. The pick is then scored against the measured table that
// `tutor site-data` exported with the example (course.ts, `Checkpoint`): good
// (within the band of the cheapest choice that meets the accuracy), costly, or
// fails (misses the accuracy). The reason is not graded: nothing here can judge
// free text, and no model is asked to. It is kept in this browser and shown
// back beside the measurements, so the learner compares their reason with the
// numbers. One pick, scored once, like a prediction (predict.ts).
import type { Checkpoint, ChoiceVerdict, Unit } from "./course";
import { predictionKey } from "./predict";

export interface ChoiceRecord {
  /** 1-based choice; 0 = the measurements were shown without choosing */
  pick: number;
  reason: string;
  verdict: ChoiceVerdict | "skipped";
}

/** A reason is one line: something written, without line breaks, at most this long. */
export const MAX_REASON = 200;

export function cleanReason(s: string): string {
  return s.replace(/\s+/g, " ").trim().slice(0, MAX_REASON);
}

export const reasonOk = (s: string) => cleanReason(s).length >= 3;

export function settleChoice(c: Checkpoint, pick: number, reason: string): ChoiceRecord {
  if (pick === 0) return { pick: 0, reason: "", verdict: "skipped" };
  return { pick, reason: cleanReason(reason), verdict: c.verdicts[pick - 1] };
}

export interface KcChoices {
  kc: string;
  good: number;
  total: number;
}

/**
 * Good choices per knowledge component, over the checkpoints in `units` that
 * have a committed pick. A record whose example no longer has a checkpoint is
 * not counted; a skipped one (pick 0) is not a choice.
 */
export function choiceRates(records: Record<string, ChoiceRecord>, units: Unit[]): KcChoices[] {
  const by = new Map<string, KcChoices>();
  for (const u of units)
    u.sections.forEach((s, i) =>
      s.examples.forEach((e, j) => {
        const r = records[predictionKey(u.id, i, j)];
        if (!e.choose || !r || r.pick === 0) return;
        const k = by.get(e.choose.kc) ?? { kc: e.choose.kc, good: 0, total: 0 };
        k.total += 1;
        if (r.verdict === "good") k.good += 1;
        by.set(e.choose.kc, k);
      }),
    );
  return [...by.values()].sort((a, b) => a.kc.localeCompare(b.kc));
}

/** Every checkpoint key of a unit, in page order (the same `<unit>/<section>/<example>` keys as predictions). */
export const unitChoiceKeys = (u: Unit) =>
  u.sections.flatMap((s, i) => s.examples.flatMap((e, j) => (e.choose ? [predictionKey(u.id, i, j)] : [])));

/** "8000 (4.7× the cheapest)" style text for one row of the measured table. */
export function costText(c: Checkpoint, i: number): string {
  const n = c.costs[i].toLocaleString("en-US");
  if (!c.ok[i]) return `${n} (misses the accuracy)`;
  return c.ratios[i] === 1 ? `${n} (the cheapest)` : `${n} (${c.ratios[i]}× the cheapest)`;
}
