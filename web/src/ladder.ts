// The performance ladder in this browser. The rungs and their states come from
// Practice.ladder in Julia (the same text `tutor practice` prints); this file
// only keeps the best climb per problem and counts them. Nothing is sent
// anywhere, and there is no ranking against other learners.

export type RungState = "reached" | "not-reached" | "not-measured" | "not-offered";

export interface Rung {
  id: "correct" | "within-2x" | "allocation-free";
  title: string;
  state: RungState;
  detail: string;
}

export interface Ladder {
  rungs: Rung[];
  /** rungs reached from the bottom, up to the first that is not */
  climbed: number;
  /** rungs this problem has (allocation-free is not offered when the reference allocates) */
  offered: number;
}

/** What is stored per problem: the highest climb so far, out of how many rungs. */
export interface LadderRecord {
  climbed: number;
  offered: number;
}

/**
 * The record after a graded attempt: the higher climb is kept (a slower rerun
 * does not take a rung away); `offered` follows the latest grade, and the climb never exceeds it.
 */
export function bestLadder(prev: LadderRecord | undefined, l: Ladder): LadderRecord {
  const climbed = Math.min(Math.max(prev?.climbed ?? 0, l.climbed), l.offered);
  return { climbed, offered: l.offered };
}

/** Rungs climbed and rungs offered over the given problems that have a record. */
export function ladderTotals(records: Record<string, LadderRecord>, problemIds: string[]) {
  let climbed = 0, offered = 0, graded = 0, top = 0;
  for (const id of problemIds) {
    const r = records[id];
    if (!r) continue;
    graded += 1; climbed += r.climbed; offered += r.offered;
    if (r.climbed === r.offered) top += 1;
  }
  return { graded, climbed, offered, top };
}

export const RUNG_MARK: Record<RungState, string> = {
  reached: "✓", "not-reached": "✗", "not-measured": "·", "not-offered": "–",
};
