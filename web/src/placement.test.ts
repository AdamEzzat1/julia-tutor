import { describe, expect, it } from "vitest";
import { course, type PlacementItem, type Unit } from "./course";
import { checkItems, clearCourse, settlePlacement, verdicts, type PlacementAnswers } from "./placement";

const item = (covers: string[], answer = 2): PlacementItem => ({
  prompt: "What does this print?", code: "1 + 1", choices: ["1", "2", "3"], answer, explain: "", misconceptions: ["a", "", "c"],
  covers, output: "2",
});
const unit = (id: string, placement: PlacementItem[] = []): Unit => ({
  id, title: id, track: "foundations", course: "t", env: "base", status: "ready", summary: "", kcs: [], prerequisites: [],
  outline: [], lessons: [], sections: [], problems: [], placement,
});

// a covers itself; b's item covers b and a; c has no item; d has two items
const units = [unit("a", [item(["a"])]), unit("b", [item(["a", "b"])]), unit("c"), unit("d", [item(["d"]), item(["d"])])];

describe("placement check", () => {
  it("lists a course's items in unit order, keyed by unit and item", () => {
    expect(checkItems(units).map((c) => c.key)).toEqual(["a/0", "b/0", "d/0", "d/1"]);
  });

  it("scores one pick against the key", () => {
    expect(settlePlacement(item(["a"]), 2)).toEqual({ pick: 2, right: true });
    expect(settlePlacement(item(["a"]), 3)).toEqual({ pick: 3, right: false });
  });

  it("skip needs every covering item right; one miss means study; no item means unchecked", () => {
    const none: PlacementAnswers = {};
    expect(verdicts(units, none)).toEqual({ a: "pending", b: "pending", c: "unchecked", d: "pending" });
    const allRight: PlacementAnswers = { "a/0": { pick: 2, right: true }, "b/0": { pick: 2, right: true },
      "d/0": { pick: 2, right: true }, "d/1": { pick: 2, right: true } };
    expect(verdicts(units, allRight)).toEqual({ a: "skip", b: "skip", c: "unchecked", d: "skip" });
    // b's item also covers a: missing it sends both back, though a's own item was right
    const missB = { ...allRight, "b/0": { pick: 1, right: false } };
    expect(verdicts(units, missB)).toMatchObject({ a: "study", b: "study" });
    // a miss decides at once, even with a covering item still unanswered
    expect(verdicts(units, { "d/1": { pick: 3, right: false } }).d).toBe("study");
    expect(verdicts(units, { "d/0": { pick: 2, right: true } }).d).toBe("pending");
  });

  it("retaking clears only this course's answers", () => {
    const answers: PlacementAnswers = { "a/0": { pick: 2, right: true }, "other/0": { pick: 1, right: false } };
    expect(clearCourse(answers, units)).toEqual({ "other/0": { pick: 1, right: false } });
  });

  it("the site data's items: answer is the recorded output, no other choice is, covers are earlier units of the course", () => {
    const items = course.units.flatMap((u) => (u.placement ?? []).map((p) => ({ u, p })));
    expect(items.length).toBeGreaterThanOrEqual(10);
    for (const { u, p } of items) {
      const own = course.units.filter((x) => x.course === u.course).map((x) => x.id);
      expect(p.choices[p.answer - 1].trimEnd(), `${u.id}: ${p.code}`).toBe(p.output.trimEnd());
      expect(p.choices.filter((c) => c.trimEnd() === p.output.trimEnd())).toHaveLength(1);
      expect(p.covers).toContain(u.id);
      for (const v of p.covers) {
        expect(own.indexOf(v), `${u.id} covers ${v}`).toBeGreaterThanOrEqual(0);
        expect(own.indexOf(v)).toBeLessThanOrEqual(own.indexOf(u.id));
      }
      expect(p.misconceptions).toHaveLength(p.choices.length);
      p.misconceptions.forEach((m, k) => expect(m === "", `${u.id} misconception ${k + 1}`).toBe(k === p.answer - 1));
    }
  });

  it("the core check covers at least half of the core course's units", () => {
    const core = course.units.filter((u) => u.course === "core");
    const v = verdicts(core, {});
    expect(Object.values(v).filter((x) => x !== "unchecked").length * 2).toBeGreaterThanOrEqual(core.length);
  });
});
