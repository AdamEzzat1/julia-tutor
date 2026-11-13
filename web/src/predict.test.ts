import { describe, expect, it } from "vitest";
import { course, type Prediction, type Unit } from "./course";
import { predictionKey, predictionRates, settlePrediction, unitPredictionKeys } from "./predict";

const P = (kc: string, answer = 2): Prediction =>
  ({ kc, prompt: "p", choices: ["a", "b", "c"], answer, explain: "e", measured: "2.79" });
const ex = (predict: Prediction | null) =>
  ({ code: "x", caption: "", notice: "", mode: "repl", check: true, output: "o", ok: true, images: [], ...(predict ? { predict } : {}) });
const unit = (id: string, preds: (Prediction | null)[]): Unit =>
  ({ id, sections: [{ title: "s", body: "", examples: preds.map(ex), questions: [] }] }) as unknown as Unit;

describe("predict, then run", () => {
  it("scores one pick; pick 0 (shown without predicting) is never a hit", () => {
    expect(settlePrediction(P("k"), 2)).toEqual({ pick: 2, hit: true });
    expect(settlePrediction(P("k"), 1)).toEqual({ pick: 1, hit: false });
    expect(settlePrediction(P("k", 0 as never), 0)).toEqual({ pick: 0, hit: false });
  });

  it("counts hits per knowledge component, leaving out skips and stale records", () => {
    const u = unit("31-x", [P("order"), null, P("order"), P("stability")]);
    const recs = {
      [predictionKey("31-x", 0, 0)]: { pick: 2, hit: true },
      [predictionKey("31-x", 0, 2)]: { pick: 3, hit: false },
      [predictionKey("31-x", 0, 3)]: { pick: 0, hit: false },     // skipped: not a prediction
      [predictionKey("31-x", 0, 1)]: { pick: 1, hit: true },      // no prediction there any more
      [predictionKey("99-gone", 0, 0)]: { pick: 1, hit: true },   // unit not in the list
    };
    expect(predictionRates(recs, [u])).toEqual([{ kc: "order", hits: 1, total: 2 }]);
    expect(unitPredictionKeys(u)).toEqual(["31-x/0/0", "31-x/0/2", "31-x/0/3"]);
  });

  it("the site data carries predictions whose answer indexes a choice and a measured value", () => {
    const preds = course.units.flatMap((u) => u.sections.flatMap((s) => s.examples.flatMap((e) => (e.predict ? [e.predict] : []))));
    expect(preds.length).toBeGreaterThanOrEqual(4);
    for (const p of preds) {
      expect(p.answer).toBeGreaterThanOrEqual(1);
      expect(p.answer).toBeLessThanOrEqual(p.choices.length);
      expect(p.measured.length).toBeGreaterThan(0);
    }
  });
});
