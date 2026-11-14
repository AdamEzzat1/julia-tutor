// Parsons problems (Phase 5): put the reference's lines in a working order.
// Which orders work is measured, not judged: `tutor course record` ran every
// arrangement (one of each line/distractor pair, every order that parses and
// is indented consistently) on the problem's cases and kept those that match
// the reference. The site checks an arrangement against that set, so it needs
// no server. Feedback mirrors `Course.parsons_feedback` (tested on the same
// vectors): a distractor shows the misconception it stands for; otherwise the
// longest prefix that starts a working order.
import type { Parsons, Problem, Unit } from "./course";

export type ParsonsFeedback =
  | { kind: "invalid" }
  | { kind: "distractor"; distractor: number }
  | { kind: "count"; need: number }
  | { kind: "solved" }
  | { kind: "prefix"; good: number };

/** The first pool index with the same text (two `end` lines are interchangeable); 1-based. */
export const canonical = (pool: string[], i: number) => pool.indexOf(pool[i - 1]) + 1;

/** Feedback on an arrangement (1-based pool indices), in Course.parsons_feedback's order. */
export function parsonsFeedback(pool: string[], n: number, accepted: number[][], order: number[]): ParsonsFeedback {
  if (order.some((i) => i < 1 || i > pool.length) || new Set(order).size !== order.length) return { kind: "invalid" };
  const d = order.find((i) => i > n);
  if (d !== undefined) return { kind: "distractor", distractor: d - n };
  if (order.length !== n) return { kind: "count", need: n };
  const key = order.map((i) => canonical(pool, i));
  if (accepted.some((a) => a.every((x, k) => x === key[k]))) return { kind: "solved" };
  let good = 0;
  for (const a of accepted) {
    let k = 0;
    while (k < n && a[k] === key[k]) k++;
    good = Math.max(good, k);
  }
  return { kind: "prefix", good };
}

/** FNV-1a over UTF-8, as Course.parsons_display_order computes it. */
function fnv(s: string): number {
  let h = 0x811c9dc5;
  for (const b of new TextEncoder().encode(s)) h = Math.imul(h ^ b, 0x01000193) >>> 0;
  return h;
}

/** A fixed shuffle of the pool (1-based indices), the same order `tutor practice` lists. */
export function displayOrder(id: string, pool: string[]): number[] {
  return pool.map((x, i) => ({ h: fnv(id + "\n" + x), i: i + 1 }))
    .sort((a, b) => a.h - b.h || a.i - b.i).map((x) => x.i);
}

export interface ParsonsRecord {
  /** checks made before it worked */
  attempts: number;
  solved: boolean;
  /** the first check was a working order */
  firstTry: boolean;
}

/** The record after one more check; a solved record never changes again. */
export function bumpParsons(r: ParsonsRecord | undefined, solved: boolean): ParsonsRecord {
  const b = r ?? { attempts: 0, solved: false, firstTry: false };
  if (b.solved) return b;
  return { attempts: b.attempts + 1, solved, firstTry: solved && b.attempts === 0 };
}

export interface KcParsons {
  kc: string;
  solved: number;
  firstTry: number;
  total: number;
}

/** Solved Parsons problems per knowledge component, over those the learner has checked (a record exists). */
export function parsonsRates(records: Record<string, ParsonsRecord>, units: Unit[]): KcParsons[] {
  const by = new Map<string, KcParsons>();
  for (const u of units)
    for (const p of u.problems) {
      const r = records[p.id];
      if (!p.parsons || !r) continue;
      const k = by.get(p.parsons.kc) ?? { kc: p.parsons.kc, solved: 0, firstTry: 0, total: 0 };
      k.total += 1;
      if (r.solved) k.solved += 1;
      if (r.firstTry) k.firstTry += 1;
      by.set(p.parsons.kc, k);
    }
  return [...by.values()].sort((a, b) => a.kc.localeCompare(b.kc));
}

/** The Parsons problems of a unit. */
export const unitParsons = (u: Unit): Problem[] => u.problems.filter((p) => p.parsons);

/** The whole program an arrangement makes (fixed lines included). */
export const assemble = (z: Parsons, order: number[]) => [...z.head, ...order.map((i) => z.pool[i - 1]), ...z.tail].join("\n");
