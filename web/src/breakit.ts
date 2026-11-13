// Break it (Phase 5): an example with a break-it challenge hides its recorded
// sweep until the learner commits the value of a parameter where the method
// stops working (a step size, a start point, a rate ratio). The edge is not
// typed by an author: `tutor site-data` read it from the recorded sweep, as
// the two swept values either side of the change (course.ts, `BreakIt`), and
// `tutor course verify` re-checks it on a fresh run. With `tutor serve`
// connected the learner can run the challenge's probe at any value first, so
// the edge can be found by measurement, not only by derivation. One commit,
// scored once, like a prediction (predict.ts).
import type { BreakIt, Unit } from "./course";
import { predictionKey } from "./predict";

export type BreakVerdict = "found" | "close" | "short" | "past";

export interface BreakRecord {
  /** the committed value; null = the sweep was shown without committing */
  value: number | null;
  verdict: BreakVerdict | "skipped";
  /** probe runs made before committing (counted, not graded) */
  probes: number;
}

// A plain positive decimal, as a learner types it: 0.24, 1.39, 2.4e-1. No
// expressions: the value is put into Julia code, so only a number may pass.
const NUMBER = /^\+?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?$/;

/** The value typed, or null when it is not a finite positive number. */
export function parseValue(s: string): number | null {
  const t = s.trim();
  if (!NUMBER.test(t)) return null;
  const v = Number(t);
  return Number.isFinite(v) && v > 0 ? v : null;
}

/**
 * Where `v` lies against the measured edge: inside it (found), within the
 * challenge's `close` factor of it, on the side where the method still works
 * (short), or well into the side where it fails (past).
 */
export function judge(b: BreakIt, v: number): BreakVerdict {
  const [lo, hi] = b.edge;
  if (v >= lo && v <= hi) return "found";
  if (v >= lo / b.close && v <= hi * b.close) return "close";
  const works = b.side === "high" ? v < lo : v > hi;
  return works ? "short" : "past";
}

export function settleBreak(b: BreakIt, v: number | null, probes: number): BreakRecord {
  return v === null ? { value: null, verdict: "skipped", probes } : { value: v, verdict: judge(b, v), probes };
}

/** The value as Julia source: JavaScript's shortest round-trip form (0.24, 1e-7, 1.5e+21) is valid Julia. */
export const juliaNumber = (v: number) => String(v);

export const probeCode = (b: BreakIt, v: number) => b.probe.split("{{p}}").join(juliaNumber(v));

/** Julia prints Inf and NaN, which Number() does not read. */
function readNumber(s: string): number {
  if (/^[-+]?Inf$/.test(s)) return s.startsWith("-") ? -Infinity : Infinity;
  if (s === "NaN") return NaN;
  const v = Number(s);
  return s.trim() === "" ? NaN : v;
}

export const failedAt = (b: BreakIt, m: number) => Number.isNaN(m) || (b.fails === "above" ? m > b.limit : m < b.limit);

/**
 * Read a probe run's output with the challenge's row regex: the measured
 * value and whether the method failed there, or null when no single row
 * matches (the run errored, or the code was changed).
 */
export function readProbe(b: BreakIt, output: string): { p: number; m: string; failed: boolean } | null {
  let re: RegExp;
  try { re = new RegExp(b.row); } catch { return null; }
  const hits = output.split("\n").map((l) => re.exec(l)).filter((x): x is RegExpExecArray => x !== null);
  if (hits.length !== 1 || !hits[0].groups) return null;
  const { p, m } = hits[0].groups;
  const pv = readNumber(p ?? ""), mv = readNumber(m ?? "");
  if (!Number.isFinite(pv)) return null;
  return { p: pv, m: m ?? "", failed: failedAt(b, mv) };
}

/** The measured rows with the learner's value placed among them (a marker row, `mine`), in order of the parameter. */
export function sweepWith(b: BreakIt, v: number | null): ({ p: number; m: string; failed: boolean; mine?: false } | { p: number; mine: true })[] {
  const rows: ({ p: number; m: string; failed: boolean; mine?: false } | { p: number; mine: true })[] = b.rows.map((r) => ({ ...r }));
  if (v === null) return rows;
  const at = rows.findIndex((r) => r.p > v);
  rows.splice(at === -1 ? rows.length : at, 0, { p: v, mine: true });
  return rows;
}

export interface KcBreaks {
  kc: string;
  found: number;
  total: number;
}

/** Edges found per knowledge component, over committed challenges in `units` (skips and stale records are not counted). */
export function breakRates(records: Record<string, BreakRecord>, units: Unit[]): KcBreaks[] {
  const by = new Map<string, KcBreaks>();
  for (const u of units)
    u.sections.forEach((s, i) =>
      s.examples.forEach((e, j) => {
        const r = records[predictionKey(u.id, i, j)];
        if (!e.breakit || !r || r.value === null) return;
        const k = by.get(e.breakit.kc) ?? { kc: e.breakit.kc, found: 0, total: 0 };
        k.total += 1;
        if (r.verdict === "found") k.found += 1;
        by.set(e.breakit.kc, k);
      }),
    );
  return [...by.values()].sort((a, b) => a.kc.localeCompare(b.kc));
}

/** Every break-it key of a unit, in page order (the same `<unit>/<section>/<example>` keys as predictions). */
export const unitBreakKeys = (u: Unit) =>
  u.sections.flatMap((s, i) => s.examples.flatMap((e, j) => (e.breakit ? [predictionKey(u.id, i, j)] : [])));
