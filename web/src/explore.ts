// Precomputed explorers (Phase 5): sliders over a grid of results that an
// example's recorded output holds (error against step size for three methods,
// growth against a stability number). `tutor site-data` read the grid from
// the output with the author's row regex and exported it only when it is a
// full grid (src/course.jl, `explorer_grid`); `tutor course verify` re-runs
// the example. Nothing here computes a result: the site looks values up and
// draws them. The values are shown exactly as the output printed them.
import type { Explorer } from "./course";

/** A point of the grid: one value index per axis, in the explorer's axis order. */
export type Selection = number[];

export function startSelection(x: Explorer): Selection {
  return x.axes.map(() => 0);
}

/** Row-major position of a point (the last axis varies fastest), as exported. */
export function flatIndex(x: Explorer, sel: Selection): number {
  return x.axes.reduce((acc, a, k) => acc * a.texts.length + sel[k], 0);
}

/** The measure at a point, as the output printed it. */
export function valueAt(x: Explorer, sel: Selection): string {
  return x.values[flatIndex(x, sel)];
}

/** A printed Julia number as a JS number (`Inf`, `-Inf`, `NaN` included). */
export function juliaValue(s: string): number {
  const t = s.trim();
  if (t === "Inf") return Infinity;
  if (t === "-Inf") return -Infinity;
  if (t === "NaN") return NaN;
  return Number(t);
}

export interface Point { x: number; v: number; text: string; index: number }
export interface Line { label: string; points: Point[]; current: boolean }

/**
 * The lines to draw: the measure against the x axis, with every other axis
 * held at the selection; one line per value of the series axis when there is
 * one (the selected value's line is `current`), otherwise one line.
 */
export function lines(x: Explorer, sel: Selection): Line[] {
  const xi = x.axes.findIndex((a) => a.group === x.x);
  const si = x.series ? x.axes.findIndex((a) => a.group === x.series) : -1;
  const along = (s: Selection): Point[] =>
    x.axes[xi].nums.map((xv, j) => {
      const p = s.slice();
      p[xi] = j;
      const text = valueAt(x, p);
      return { x: xv, v: juliaValue(text), text, index: j };
    });
  if (si < 0) return [{ label: x.label, points: along(sel), current: true }];
  return x.axes[si].texts.map((label, k) => {
    const s = sel.slice();
    s[si] = k;
    return { label, points: along(s), current: k === sel[si] };
  });
}

/**
 * The slope on log-log axes between the selected point and its neighbour on
 * the x axis (the next one, or the previous at the end), from the printed
 * values: `log(v2 / v1) / log(x2 / x1)`. Null unless both the x axis and the
 * measure are on log scales and both values are positive and finite.
 */
export function localSlope(x: Explorer, sel: Selection): { slope: number; from: string; to: string } | null {
  const xi = x.axes.findIndex((a) => a.group === x.x);
  const ax = x.axes[xi];
  if (!x.log || !ax.log) return null;
  const j = sel[xi];
  const k = j + 1 < ax.nums.length ? j + 1 : j - 1;
  const [a, b] = j < k ? [j, k] : [k, j];
  const at = (i: number) => { const s = sel.slice(); s[xi] = i; return juliaValue(valueAt(x, s)); };
  const va = at(a), vb = at(b);
  if (!(va > 0 && vb > 0 && Number.isFinite(va) && Number.isFinite(vb))) return null;
  return { slope: Math.log(vb / va) / Math.log(ax.nums[b] / ax.nums[a]), from: ax.texts[a], to: ax.texts[b] };
}

/** Whether a value can be drawn on an axis (log: positive and finite; linear: finite). */
export function drawable(v: number, log: boolean): boolean {
  return Number.isFinite(v) && (!log || v > 0);
}

/** A map from data to pixels on [p0, p1], linear or log, over the given extent. */
export function scale(lo: number, hi: number, p0: number, p1: number, log: boolean): (v: number) => number {
  const f = log ? Math.log10 : (v: number) => v;
  let a = f(lo), b = f(hi);
  if (a === b) { a -= 1; b += 1; }   // a flat line still gets an axis
  return (v: number) => p0 + ((f(v) - a) / (b - a)) * (p1 - p0);
}

/** Ticks for an axis: powers of ten for a log axis (thinned to at most 6), the data's own values otherwise. */
export function ticks(lo: number, hi: number, log: boolean, values: number[]): number[] {
  if (!log) {
    const u = [...new Set(values)].sort((p, q) => p - q);
    const step = Math.ceil(u.length / 6);
    return u.filter((_, i) => i % step === 0);
  }
  const out: number[] = [];
  for (let e = Math.floor(Math.log10(lo)); e <= Math.ceil(Math.log10(hi)); e++) out.push(10 ** e);
  const step = Math.ceil(out.length / 6);
  return out.filter((_, i) => i % step === 0);
}

/** The measure's extent over every drawable value in the grid, so the axes stay put while sliders move. */
export function extent(vals: number[], log: boolean): [number, number] | null {
  const d = vals.filter((v) => drawable(v, log));
  if (d.length === 0) return null;
  return [Math.min(...d), Math.max(...d)];
}
