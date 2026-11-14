import { describe, expect, it } from "vitest";
import { course, type Example, type Explorer } from "./course";
import { drawable, extent, flatIndex, juliaValue, lines, localSlope, scale, startSelection, ticks, valueAt } from "./explore";

const explorers: { unit: string; ex: Example; x: Explorer }[] = course.units.flatMap((u) =>
  u.sections.flatMap((s) => s.examples.filter((e) => e.explore).map((ex) => ({ unit: u.id, ex, x: ex.explore! }))));
const find = (unit: string) => explorers.find((e) => e.unit === unit)!.x;
const at = (x: Explorer, ...texts: string[]) => x.axes.map((a, k) => a.texts.indexOf(texts[k]));

describe("precomputed explorers", () => {
  it("the course has the three explorers, each a full grid", () => {
    expect(explorers.map((e) => e.unit).sort()).toEqual(["30-floating-point", "31-convergence", "34-pde-discretization"]);
    for (const { x } of explorers) {
      expect(x.values.length).toBe(x.axes.reduce((n, a) => n * a.texts.length, 1));
      expect(x.axes.some((a) => a.group === x.x && a.numeric)).toBe(true);
    }
  });

  it("every point's value is the one printed on its own line of the recorded output", () => {
    // Walks the whole grid: a wrong row-major index would pair a value with another point's axes.
    for (const { ex, x } of explorers) {
      const outLines = ex.output!.split("\n");
      const walk = (k: number, sel: number[]) => {
        if (k === x.axes.length) {
          const parts = [...x.axes.map((a, i) => a.texts[sel[i]]), valueAt(x, sel)];
          const hit = outLines.some((l) => {
            let from = 0;
            return parts.every((p) => {
              const re = new RegExp(`(^|[\\s=])${p.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}(?=$|\\s)`, "g");
              re.lastIndex = from;
              const m = re.exec(l);
              if (!m) return false;
              from = m.index + m[0].length;
              return true;
            });
          });
          expect(hit, `${parts.join(" ")} in ${ex.caption.slice(0, 40)}`).toBe(true);
          return;
        }
        for (let j = 0; j < x.axes[k].texts.length; j++) walk(k + 1, [...sel, j]);
      };
      walk(0, []);
    }
  });

  it("looks values up as printed, row-major with the last axis fastest", () => {
    const c = find("31-convergence");
    expect(c.axes.map((a) => a.group)).toEqual(["method", "h"]);
    expect(valueAt(c, at(c, "RK4", "0.4"))).toBe("2.0e-5");
    expect(flatIndex(c, at(c, "Euler", "0.025"))).toBe(1);   // h is sorted ascending: 0.0125, 0.025, ...
    const p = find("34-pde-discretization");
    expect(valueAt(p, at(p, "forward", "19", "0.52"))).toBe("5.53");
    expect(valueAt(p, at(p, "backward", "79", "1.0"))).toBe("0.99");
    expect(startSelection(p)).toEqual([0, 0, 0]);
  });

  it("one line per series value, holding the other axes at the selection", () => {
    const p = find("34-pde-discretization");
    const ls = lines(p, at(p, "backward", "39", "0.5"));
    expect(ls.map((l) => [l.label, l.current])).toEqual([["forward", false], ["backward", true]]);
    expect(ls[0].points.map((q) => q.text)).toEqual(["0.98", "0.949", "0.93", "0.918", "0.908", "3.6", "1.13e+05", "5.9e+11", "5.29e+22", "9.36e+44"]);
    expect(ls[0].points.map((q) => q.x)).toEqual(p.axes[2].nums);
  });

  it("the slope between printed neighbours on log-log axes, and none otherwise", () => {
    const c = find("31-convergence");
    // RK4 from h = 0.4 to 0.2: log(2.0e-5 / 1.3e-7) / log(2) = 7.27 (the explanation's 7.3)
    const s = localSlope(c, at(c, "RK4", "0.2"))!;
    expect([s.from, s.to]).toEqual(["0.2", "0.4"]);
    expect(s.slope).toBeCloseTo(Math.log2(2.0e-5 / 1.3e-7), 12);
    // the last point pairs with the one before it; Euler's slope is 1 to the printed digits
    const e = localSlope(c, at(c, "Euler", "0.4"))!;
    expect([e.from, e.to]).toEqual(["0.2", "0.4"]);
    expect(e.slope).toBeCloseTo(1, 12);
    // a linear x axis (r) has no log-log slope
    const p = find("34-pde-discretization");
    expect(localSlope(p, at(p, "forward", "19", "0.3"))).toBeNull();
  });

  it("parses Julia's printed numbers and draws only what the scale can hold", () => {
    expect([juliaValue("Inf"), juliaValue("-Inf"), juliaValue("2.09e+05"), juliaValue("1.0e-15")]).toEqual([Infinity, -Infinity, 209000, 1e-15]);
    expect(Number.isNaN(juliaValue("NaN"))).toBe(true);
    expect([drawable(0, true), drawable(0, false), drawable(Infinity, false), drawable(1e-300, true)]).toEqual([false, true, false, true]);
    expect(extent([0, 1e-3, 10, NaN], true)).toEqual([1e-3, 10]);
    expect(extent([NaN], false)).toBeNull();
  });

  it("scales map the extent onto the pixel range, log or linear", () => {
    const lg = scale(1e-3, 10, 0, 400, true);
    expect([lg(1e-3), lg(1e-1), lg(10)].map((v) => Math.round(v))).toEqual([0, 200, 400]);
    const lin = scale(0.3, 1.0, 100, 0, false);
    expect(lin(0.3)).toBe(100);
    expect(lin(1.0)).toBe(0);
    expect(scale(2, 2, 0, 10, false)(2)).toBe(5);   // a flat line still gets an axis
    expect(ticks(1e-12, 1e-2, true, [])).toEqual([1e-12, 1e-10, 1e-8, 1e-6, 1e-4, 1e-2]);
    expect(ticks(0, 0, false, [0.3, 0.4, 0.5])).toEqual([0.3, 0.4, 0.5]);
  });
});
