import { describe, expect, it } from "vitest";
import { course, type BreakIt, type Unit } from "./course";
import { breakRates, judge, parseValue, probeCode, readProbe, settleBreak, sweepWith, unitBreakKeys } from "./breakit";

const B = (kc: string, side: "high" | "low" = "high"): BreakIt => ({
  kc, prompt: "p", param: "h", measure: "growth", fails: "above", limit: 1, close: 1.25, edge: [0.2, 0.25], side,
  probe: "h = {{p}}\nprintln(h)", row: String.raw`h = (?<p>\S+) +growth (?<m>\S+)`, explain: "e", short: "s", past: "x",
  rows: [{ p: 0.1, m: "0.01", failed: side === "low" }, { p: 0.2, m: "0.9", failed: side === "low" },
         { p: 0.25, m: "1.5", failed: side === "high" }, { p: 0.4, m: "Inf", failed: side === "high" }],
});
const ex = (breakit: BreakIt | null) =>
  ({ code: "", caption: "", notice: "", mode: "repl", check: true, output: "", ok: true, images: [], ...(breakit ? { breakit } : {}) });
const unit = (id: string, bs: (BreakIt | null)[]): Unit =>
  ({ id, sections: [{ title: "s", body: "", examples: bs.map(ex), questions: [] }] }) as unknown as Unit;

describe("break it", () => {
  it("accepts only a plain positive number as the value", () => {
    expect(parseValue(" 0.24 ")).toBe(0.24);
    expect(parseValue("2.4e-1")).toBe(0.24);
    expect(parseValue(".5")).toBe(0.5);
    for (const bad of ["", "0", "-1", "6/25", "1e400", "0.2; run(`ls`)", "Inf", "1,5"]) expect(parseValue(bad)).toBeNull();
  });

  it("judges a value against the measured edge, on either failing side", () => {
    const hi = B("k");
    expect(judge(hi, 0.24)).toBe("found");
    expect(judge(hi, 0.2)).toBe("found");          // the edge's ends are inside it
    expect(judge(hi, 0.17)).toBe("close");         // within 1.25 of the low end
    expect(judge(hi, 0.3)).toBe("close");
    expect(judge(hi, 0.1)).toBe("short");          // the method still works there
    expect(judge(hi, 0.4)).toBe("past");           // it fails there, far past the edge
    const lo = B("k", "low");
    expect(judge(lo, 0.1)).toBe("past");
    expect(judge(lo, 0.4)).toBe("short");
    expect(settleBreak(hi, 0.24, 3)).toEqual({ value: 0.24, verdict: "found", probes: 3 });
    expect(settleBreak(hi, null, 0)).toEqual({ value: null, verdict: "skipped", probes: 0 });
  });

  it("puts the value into the probe as a Julia literal and reads the probe's one row back", () => {
    expect(probeCode(B("k"), 0.24)).toBe("h = 0.24\nprintln(h)");
    expect(probeCode(B("k"), 1e-7)).toBe("h = 1e-7\nprintln(h)");
    expect(readProbe(B("k"), "h = 0.3  growth 9.5\n")).toEqual({ p: 0.3, m: "9.5", failed: true });
    expect(readProbe(B("k"), "h = 0.1  growth 0.5\n")).toEqual({ p: 0.1, m: "0.5", failed: false });
    expect(readProbe(B("k"), "h = 2.0  growth Inf\n")?.failed).toBe(true);
    expect(readProbe(B("k"), "h = 2.0  growth NaN\n")?.failed).toBe(true);   // a broken-down run failed
    expect(readProbe(B("k"), "ERROR: UndefVarError\n")).toBeNull();
    expect(readProbe(B("k"), "h = 0.1  growth 0.5\nh = 0.2  growth 0.6\n")).toBeNull();   // one row, not two
  });

  it("places the learner's value among the measured rows", () => {
    const rows = sweepWith(B("k"), 0.22);
    expect(rows.map((r) => r.p)).toEqual([0.1, 0.2, 0.22, 0.25, 0.4]);
    expect(rows[2].mine).toBe(true);
    const end = sweepWith(B("k"), 9);
    expect(end[end.length - 1].mine).toBe(true);
    expect(sweepWith(B("k"), null).length).toBe(4);
  });

  it("counts found edges per KC, leaving out skips and records without a challenge", () => {
    const u = unit("35-x", [B("stability"), null, B("stability"), B("root-finding")]);
    const rates = breakRates({
      "35-x/0/0": { value: 0.24, verdict: "found", probes: 2 },
      "35-x/0/1": { value: 0.24, verdict: "found", probes: 0 },     // the example has no challenge (stale)
      "35-x/0/2": { value: 0.4, verdict: "past", probes: 0 },
      "35-x/0/3": { value: null, verdict: "skipped", probes: 0 },
    }, [u]);
    expect(rates).toEqual([{ kc: "stability", found: 1, total: 2 }]);
    expect(unitBreakKeys(u)).toEqual(["35-x/0/0", "35-x/0/2", "35-x/0/3"]);
  });

  it("the site data carries sweeps with one edge, readable by the browser's own regex", () => {
    const exs = course.units.flatMap((u) => u.sections.flatMap((s) => s.examples.filter((e) => e.breakit)));
    expect(exs.length).toBeGreaterThanOrEqual(3);
    for (const e of exs) {
      const b = e.breakit!;
      const ps = b.rows.map((r) => r.p);
      expect([...ps].sort((x, y) => x - y)).toEqual(ps);
      const changes = b.rows.slice(1).filter((r, i) => r.failed !== b.rows[i].failed).length;
      expect(changes).toBe(1);
      const i = b.rows.findIndex((r, k) => k > 0 && r.failed !== b.rows[k - 1].failed);
      expect([b.rows[i - 1].p, b.rows[i].p]).toEqual(b.edge);
      expect(b.rows[b.rows.length - 1].failed).toBe(b.side === "high");
      expect(b.probe).toContain("{{p}}");
      // The probe's output is read in the browser with JavaScript's regex, the sweep in Julia with PCRE: each
      // recorded line must read back to the same row (a pattern the two engines disagree on would fail here).
      const lines = (e.output ?? "").split("\n").filter((l) => new RegExp(b.row).test(l));
      expect(lines.map((l) => readProbe(b, l))).toEqual(b.rows);
    }
  });
});
