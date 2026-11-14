import { describe, expect, it } from "vitest";
import { course, type Checkpoint, type Unit } from "./course";
import { choiceRates, cleanReason, costText, reasonOk, settleChoice, unitChoiceKeys } from "./choose";

const C = (kc: string): Checkpoint => ({
  kc, prompt: "p", choices: ["A", "B", "C"], cost: "calls", band: 2, explain: "e", misconceptions: ["slow", "", "off"],
  costs: [900, 120, 50], ok: [true, true, false], ratios: [7.5, 1, 0.417], verdicts: ["costly", "good", "fails"],
});
const ex = (choose: Checkpoint | null) =>
  ({ code: "", caption: "", notice: "", mode: "repl", check: true, output: "", ok: true, images: [], ...(choose ? { choose } : {}) });
const unit = (id: string, cks: (Checkpoint | null)[]): Unit =>
  ({ id, sections: [{ title: "s", body: "", examples: cks.map(ex), questions: [] }] }) as unknown as Unit;

describe("method-choice checkpoints", () => {
  it("scores a pick by the measured verdict and keeps the reason as one trimmed line", () => {
    expect(settleChoice(C("k"), 2, "  implicit,\n stiff  ")).toEqual({ pick: 2, reason: "implicit, stiff", verdict: "good" });
    expect(settleChoice(C("k"), 1, "cheap steps").verdict).toBe("costly");
    expect(settleChoice(C("k"), 3, "fewest calls").verdict).toBe("fails");
    expect(settleChoice(C("k"), 0, "ignored")).toEqual({ pick: 0, reason: "", verdict: "skipped" });
    expect(reasonOk("  ")).toBe(false);
    expect(reasonOk("ILU")).toBe(true);
    expect(cleanReason("x".repeat(500)).length).toBe(200);
  });

  it("counts good choices per KC, leaving out skips and records without a checkpoint", () => {
    const u = unit("35-x", [C("stiffness"), null, C("stiffness"), C("jacobian")]);
    const rates = choiceRates({
      "35-x/0/0": { pick: 2, reason: "r", verdict: "good" },
      "35-x/0/1": { pick: 1, reason: "r", verdict: "good" },      // the example has no checkpoint (stale)
      "35-x/0/2": { pick: 1, reason: "r", verdict: "costly" },
      "35-x/0/3": { pick: 0, reason: "", verdict: "skipped" },
    }, [u]);
    expect(rates).toEqual([{ kc: "stiffness", good: 1, total: 2 }]);
    expect(unitChoiceKeys(u)).toEqual(["35-x/0/0", "35-x/0/2", "35-x/0/3"]);
  });

  it("describes each measured row", () => {
    expect(costText(C("k"), 0)).toBe("900 (7.5× the cheapest)");
    expect(costText(C("k"), 1)).toBe("120 (the cheapest)");
    expect(costText(C("k"), 2)).toBe("50 (misses the accuracy)");
  });

  it("the site data carries consistent checkpoints: one row per choice, a good one and a non-good one", () => {
    const cks = course.units.flatMap((u) => u.sections.flatMap((s) => s.examples.flatMap((e) => (e.choose ? [e.choose] : []))));
    expect(cks.length).toBeGreaterThanOrEqual(3);
    for (const c of cks) {
      const n = c.choices.length;
      expect([c.costs, c.ok, c.ratios, c.verdicts, c.misconceptions].every((a) => a.length === n)).toBe(true);
      expect(c.verdicts).toContain("good");
      expect(c.verdicts.some((v) => v !== "good")).toBe(true);
      c.verdicts.forEach((v, i) => { if (v !== "good") expect(c.misconceptions[i]).not.toBe(""); });
    }
  });
});
