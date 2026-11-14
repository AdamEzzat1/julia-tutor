import { describe, expect, it } from "vitest";
import { course, type Parsons, type Problem, type Unit } from "./course";
import { assemble, bumpParsons, canonical, displayOrder, parsonsFeedback, parsonsRates, unitParsons } from "./parsons";

const Z = (kc: string): Parsons =>
  ({ kc, head: ["function f()"], tail: ["end"], pool: ["a", "b", "end", "end", "x"], n: 4,
     distractors: [{ index: 5, replaces: 1, misconception: "m" }], accepted: [[1, 2, 3, 3], [2, 1, 3, 3]] });
const P = (id: string, z: Parsons | null): Problem =>
  ({ id, title: "t", difficulty: "core", kcs: [], prompt: "", entry: "f", starter: "", hints: [], samples: [], compare: "isequal",
     rtol: 1e-8, check_type: true, random_cases: false, perf: null, ...(z ? { parsons: z } : {}) });
const unit = (id: string, ps: Problem[]): Unit => ({ id, sections: [], problems: ps }) as unknown as Unit;

describe("Parsons problems", () => {
  // The same vectors as test/course_tests.jl ("Parsons problems"), so both sides answer alike.
  const z = Z("k");
  const fb = (o: number[]) => parsonsFeedback(z.pool, z.n, z.accepted, o);

  it("gives feedback in Course.parsons_feedback's order", () => {
    expect(fb([1, 1, 3, 4])).toEqual({ kind: "invalid" });
    expect(fb([1, 2, 3, 6])).toEqual({ kind: "invalid" });
    expect(fb([1, 5, 3, 4])).toEqual({ kind: "distractor", distractor: 1 });
    expect(fb([1, 2, 3])).toEqual({ kind: "count", need: 4 });
    expect(fb([2, 1, 4, 3])).toEqual({ kind: "solved" });          // the two `end` lines are interchangeable
    expect(fb([1, 3, 2, 4])).toEqual({ kind: "prefix", good: 1 });
    expect(fb([3, 1, 2, 4])).toEqual({ kind: "prefix", good: 0 });
    expect([2, 1, 4, 3].map((i) => canonical(z.pool, i))).toEqual([2, 1, 3, 3]);
  });

  it("assembles the whole program with the fixed lines", () => {
    expect(assemble(z, [1, 2, 3, 4])).toBe("function f()\na\nb\nend\nend\nend");
  });

  it("freezes a record once the order works, and counts a first-try solve", () => {
    const once = bumpParsons(undefined, true);
    expect(once).toEqual({ attempts: 1, solved: true, firstTry: true });
    expect(bumpParsons(once, false)).toBe(once);
    const later = bumpParsons(bumpParsons(undefined, false), true);
    expect(later).toEqual({ attempts: 2, solved: true, firstTry: false });
  });

  it("counts solved problems per knowledge component, over the checked ones only", () => {
    const u = unit("u", [P("a", Z("k1")), P("b", Z("k1")), P("c", Z("k2")), P("d", null)]);
    const rates = parsonsRates({ a: { attempts: 1, solved: true, firstTry: true }, c: { attempts: 3, solved: false, firstTry: false } }, [u]);
    expect(rates).toEqual([{ kc: "k1", solved: 1, firstTry: 1, total: 1 }, { kc: "k2", solved: 0, firstTry: 0, total: 1 }]);
    expect(unitParsons(u).map((p) => p.id)).toEqual(["a", "b", "c"]);
  });

  it("shuffles the pool the way `tutor practice` lists it", () => {
    const o = displayOrder("p", z.pool);
    expect([...o].sort()).toEqual([1, 2, 3, 4, 5]);
    expect(displayOrder("p", z.pool)).toEqual(o);
    // fp-kahan-parsons as `tutor practice fp-kahan-parsons` printed it (letters a..j)
    const k = course.units.flatMap((u) => u.problems).find((p) => p.id === "fp-kahan-parsons");
    expect(k?.parsons).toBeDefined();
    expect(displayOrder("fp-kahan-parsons", k!.parsons!.pool)).toEqual([3, 8, 1, 9, 2, 5, 4, 10, 7, 6]);
  });

  it("carries a measured accepted set with the reference's order on every course problem", () => {
    const zs = course.units.flatMap((u) => u.problems).filter((p) => p.parsons);
    expect(zs.length).toBeGreaterThanOrEqual(3);
    for (const p of zs) {
      const q = p.parsons!;
      expect(q.accepted.some((a) => a.every((x, i) => x === i + 1) && a.length === q.n)).toBe(true);
      // no working order uses a distractor
      expect(q.accepted.every((a) => a.every((x) => x <= q.n))).toBe(true);
      expect(parsonsFeedback(q.pool, q.n, q.accepted, q.pool.slice(0, q.n).map((_, i) => i + 1))).toEqual({ kind: "solved" });
    }
  });
});
