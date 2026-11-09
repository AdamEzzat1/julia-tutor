import { describe, expect, it } from "vitest";
import { commands, guided, orderedProjects } from "./guided";

describe("guided projects data", () => {
  it("has the eight projects, all ready, and names pybridge's graded function", () => {
    expect(guided.projects.length).toBeGreaterThanOrEqual(8);
    expect(guided.projects.filter((p) => p.status === "ready").length).toBeGreaterThanOrEqual(8);
    const pb = guided.projects.find((p) => p.name === "pybridge")!;
    expect(pb.milestones[3].perf_entry).toBe("moving_average");
    expect(pb.milestones.filter((m) => m.perf_entry !== "").length).toBe(1);
  });

  it("numbers milestones from 0 and publishes only the first hint level", () => {
    for (const p of guided.projects) {
      expect(p.milestones.map((m) => m.id)).toEqual(p.milestones.map((_, i) => i));
      for (const m of p.milestones) {
        // Levels 2 and 3 fade in from `tutor guided check`; the site must not bypass that.
        for (const b of m.behaviours) {
          expect(b.hints.length).toBe(1);
          expect(b.test_hints.length).toBeLessThanOrEqual(1);
        }
        for (const c of m.must_cover) expect(m.behaviours.some((b) => b.id === c)).toBe(true);
        if (p.status === "ready" && m.must_cover.length > 0) expect(m.mutants).toBeGreaterThan(0);
      }
    }
  });

  it("exports specs only: no acceptance tests, reference code or mutant edits", () => {
    const text = JSON.stringify(guided);
    expect(text).not.toMatch(/@testset \\"/); // a named test set: test code, not the prose that mentions @testset
    expect(text).not.toMatch(/# Acceptance, milestone/);
    expect(text).not.toMatch(/"find"|"replace"/);
    expect(text).not.toMatch(/MISSING_MARKERS|DEFAULT_H/); // names that exist only in the references
  });

  it("orders ready projects first and gives runnable commands", () => {
    const o = orderedProjects();
    const firstPlanned = o.findIndex((p) => p.status === "planned");
    if (firstPlanned >= 0) expect(o.slice(firstPlanned).every((p) => p.status === "planned")).toBe(true);
    const tidy = guided.projects.find((p) => p.name === "tidy")!;
    expect(commands(tidy)[0]).toBe("./tutor guided start tidy work/tidy");
  });
});
