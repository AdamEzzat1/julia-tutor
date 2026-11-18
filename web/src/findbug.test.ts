import { describe, expect, it } from "vitest";
import { course, type Bug, type BugTest, type Problem, type Unit } from "./course";
import { bugRates, bugTestCode, bugTestPasses, bumpBug, hintsOpen, isPerfBug, perfCost, readBugTest, reading, testsNoun, unitBugs } from "./findbug";

const T = (expect: [number, number] = [3.7, 4.3]): BugTest =>
  ({ name: "order", code: "println(\"observed order: \", 4.0)", row: String.raw`^observed order: (?<m>\S+)$`, expect, explain: "e" });
const bug = (kc: string): Bug => ({ kc, misconception: "m", planted: "a", fixed: "b", tests: [T()] });
const P = (id: string, b: Bug | null): Problem =>
  ({ id, title: "t", difficulty: "core", kcs: [], prompt: "", entry: "f", starter: "", hints: [], samples: [], compare: "isequal",
     rtol: 1e-8, check_type: true, random_cases: false, perf: null, ...(b ? { bug: b } : {}) });
const unit = (id: string, ps: Problem[]): Unit => ({ id, sections: [], problems: ps }) as unknown as Unit;

describe("find the bug", () => {
  it("runs a test after the learner's code, as Julia's bug_test_code does", () => {
    expect(bugTestCode("f(x) = x\n\n  \n", T())).toBe("f(x) = x\n\nprintln(\"observed order: \", 4.0)");
  });

  it("reads one measured line, and nothing from zero or two", () => {
    const t = T();
    expect(readBugTest(t, "rk4_solve (generic function with 1 method)\nobserved order: 4.03\n")).toBe(4.03);
    expect(readBugTest(t, "observed order: Inf\n")).toBe(Infinity);
    expect(readBugTest(t, "observed order: NaN\n")).toBeNaN();
    expect(readBugTest(t, "ERROR: UndefVarError: `rk4_solve` not defined\n")).toBeNull();
    expect(readBugTest(t, "observed order: 4.0\nobserved order: 4.1\n")).toBeNull();
    expect(readBugTest(t, "observed order: x\n")).toBeNull();
    expect(readBugTest(T([0, 1e-9]), "observed order: 3.3306690738754696e-16")).toBeCloseTo(3.33e-16, 18);
  });

  it("passes inside the inclusive range; no reading or NaN fails", () => {
    const t = T();
    expect(bugTestPasses(t, 4.03)).toBe(true);
    expect(bugTestPasses(t, 3.7)).toBe(true);
    expect(bugTestPasses(t, 0.99)).toBe(false);
    expect(bugTestPasses(t, null)).toBe(false);
    expect(bugTestPasses(t, NaN)).toBe(false);
    expect(reading(t, "observed order: 0.99")).toEqual({ name: "order", value: 0.99, passed: false });
  });

  it("opens hints after a test run, or at once when the tests cannot run here", () => {
    expect(hintsOpen(0, true)).toBe(false);
    expect(hintsOpen(1, true)).toBe(true);
    expect(hintsOpen(0, false)).toBe(true);
  });

  it("counts runs and hints until fixed, then freezes the record", () => {
    let r = bumpBug(undefined, "run");
    r = bumpBug(r, "hint");
    r = bumpBug(r, "run");
    expect(r).toEqual({ runs: 2, hints: 1, fixed: false });
    r = bumpBug(r, "fixed");
    expect(bumpBug(bumpBug(r, "hint"), "run")).toEqual({ runs: 2, hints: 1, fixed: true });
  });

  it("counts fixes per KC over problems worked on, with the hints used on the fixed ones", () => {
    const u = unit("31-x", [P("a", bug("order")), P("b", bug("order")), P("c", null), P("d", bug("bc"))]);
    expect(unitBugs(u).map((p) => p.id)).toEqual(["a", "b", "d"]);
    expect(bugRates({ a: { runs: 3, hints: 2, fixed: true }, b: { runs: 1, hints: 1, fixed: false },
                      c: { runs: 1, hints: 0, fixed: true } }, [u]))
      .toEqual([{ kc: "order", fixed: 1, hints: 2, total: 2 }]);
  });

  it("the site data's bug problems: the starter has the planted line, not the fix, and every test reads in JavaScript", () => {
    const ps = course.units.flatMap((u) => u.problems.filter((p) => p.bug));
    expect(ps.length).toBeGreaterThanOrEqual(3);
    for (const p of ps) {
      const b = p.bug!;
      expect(p.starter).toContain(b.planted);
      expect(p.starter).not.toContain(b.fixed);
      expect(p.hints.length).toBeGreaterThan(0);
      expect(b.tests.length).toBeGreaterThan(0);
      for (const t of b.tests) {
        expect(new RegExp(t.row).source).toContain("(?<m>");
        expect(t.expect[0]).toBeLessThan(t.expect[1]);
        expect(t.code).toContain(p.entry);   // a test exercises the learner's function
      }
    }
  });

  it("names a performance bug by what it costs, and its tests by what they measure", () => {
    expect(isPerfBug(bug("k"))).toBe(false);
    expect(testsNoun(bug("k"))).toBe("convergence tests");
    const alloc = { ...bug("k"), starter_expect: ["correct", "allocates"] };
    const both = { ...bug("k"), starter_expect: ["correct", "allocates", "unstable"] };
    expect(isPerfBug(alloc)).toBe(true);
    expect(testsNoun(alloc)).toBe("measurement tests");
    expect(perfCost(alloc)).toBe("allocates");
    expect(perfCost(both)).toBe("allocates and is type-unstable");
  });

  it("the site data's Core performance bugs: correct starters, measured with @allocated or inference", () => {
    const core = course.units.filter((u) => u.course === "core").flatMap((u) => u.problems.filter((p) => p.bug && isPerfBug(p.bug)));
    expect(core.length).toBeGreaterThanOrEqual(4);
    for (const p of core) {
      const se = p.bug!.starter_expect!;
      expect(se.every((v) => ["correct", "allocates", "unstable"].includes(v))).toBe(true);
      expect(se.some((v) => v !== "correct")).toBe(true);
      expect(p.perf).not.toBeNull();
      expect(p.bug!.tests.some((t) => /@allocated|code_typed|return_types/.test(t.code))).toBe(true);
    }
  });
});
