// The scoring of one predict-the-output check, ported from Lessons.run_lesson
// (src/lessons.jl) so the browser and the CLI update the learner model the same
// way:
// * BKT observes the FIRST try only, with p_guess = 1/k for k options;
// * SM-2 quality 5 (right first try), 3 (right after the hint), 1 (revealed);
// * only the first wrong choice's misconception is counted.
import type { Check, Lesson } from "./data";
import { bktParams, bktUpdate, sm2Due, sm2Initial, sm2Update } from "./models";
import type { WebState } from "./storage";

export type Outcome = "first-try" | "second-try" | "revealed";

export function outcomeOf(check: Check, first: number, second: number | null): Outcome {
  if (first === check.answer) return "first-try";
  return second === check.answer ? "second-try" : "revealed";
}

export function settleCheck(
  state: WebState, lesson: Lesson, check: Check, first: number, second: number | null, today: string,
): WebState {
  const next: WebState = {
    kc: { ...state.kc }, items: { ...state.items }, misconceptions: { ...state.misconceptions },
  };
  const outcome = outcomeOf(check, first, second);
  const correct = outcome === "first-try";
  const quality = outcome === "first-try" ? 5 : outcome === "second-try" ? 3 : 1;
  if (!correct) {
    const mis = check.misconceptions.find((m) => m.option === first);
    if (mis) next.misconceptions[mis.id] = (next.misconceptions[mis.id] ?? 0) + 1;
  }
  const θ = bktParams({ pGuess: 1 / check.options.length });
  for (const kc of lesson.kcs) {
    next.kc[kc] = bktUpdate(next.kc[kc] ?? θ.pInit, correct, θ);
  }
  const key = `${lesson.id}/${check.id}`;
  const prev = next.items[key] ?? { ...sm2Initial(), due: today };
  const s = sm2Update(prev, quality);
  next.items[key] = { ...s, due: sm2Due(s, today) };
  return next;
}

/** A lesson counts as started once any of its checks has a record (as in the CLI). */
export const lessonStarted = (state: WebState, id: string) =>
  Object.keys(state.items).some((k) => k.startsWith(`${id}/`));

export const dueItems = (state: WebState, today: string) =>
  Object.entries(state.items).filter(([, v]) => v.due <= today).map(([k]) => k).sort();
