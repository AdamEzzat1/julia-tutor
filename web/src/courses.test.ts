// The course split (docs/COURSES_PLAN.md, Phase 1): the site data is one file
// per course plus an index, and progress saved before the split still counts.
import { describe, expect, it } from "vitest";
import { assembleCourse, course, courseOf } from "./course";
import { progressByCourse, type Progress } from "./progress";
import saved from "./fixtures/progress_v1.json";

describe("course site data", () => {
  it("has every course, each unit once, in syllabus order", () => {
    expect(course.courses.map((c) => c.id)).toEqual(["core", "science", "scicomp", "sciml"]);
    const ids = course.units.map((u) => u.id);
    expect(new Set(ids).size).toBe(ids.length);
    expect(ids).toEqual([...ids].sort());
    expect(ids).toEqual(course.courses.flatMap((c) => c.units));
    for (const u of course.units) expect(courseOf(u.id)?.id).toBe(u.course);
  });
  it("counts problems per course from the units", () => {
    for (const c of course.courses) {
      const n = course.units.filter((u) => u.course === c.id).reduce((s, u) => s + u.problems.length, 0);
      expect(c.problems).toBe(n);
    }
    expect(course.courses.reduce((s, c) => s + c.problems, 0)).toBe(141);
  });
  it("resolves cross-course prerequisites to unit ids that exist", () => {
    const ids = new Set(course.units.map((u) => u.id));
    for (const u of course.units) for (const p of u.prerequisites) expect(ids.has(p)).toBe(true);
  });
  it("marks Scientific ML as in progress", () => {
    expect(course.courses.find((c) => c.id === "sciml")?.status).toBe("in-progress");
  });
  it("refuses a stale split: a missing or unknown course file", () => {
    const idx = { ...course, units: undefined } as never;
    const files = course.courses.map((c) => ({ course: c.id, units: course.units.filter((u) => u.course === c.id) }));
    expect(() => assembleCourse(idx, files.slice(1))).toThrow(/no course file for core/);
    expect(() => assembleCourse(idx, [...files, { course: "physics", units: [] }])).toThrow(/unknown course physics/);
    expect(assembleCourse(idx, [...files].reverse()).units.map((u) => u.id)).toEqual(course.units.map((u) => u.id));
  });
});

describe("progress saved before the split", () => {
  it("maps every stored key to a course, with nothing renamed", () => {
    const { byCourse, unmapped } = progressByCourse(saved as unknown as Progress, course.courses, course.units);
    expect(unmapped).toEqual([]);
    expect(byCourse.core).toEqual({ solved: 1, opened: 1, questions: 1, predictions: 0, choices: 0 });
    expect(byCourse.science).toEqual({ solved: 0, opened: 1, questions: 0, predictions: 0, choices: 0 });
    expect(byCourse.scicomp).toEqual({ solved: 1, opened: 1, questions: 1, predictions: 0, choices: 0 });
    expect(byCourse.sciml).toEqual({ solved: 1, opened: 1, questions: 0, predictions: 0, choices: 0 });
  });
  it("reports keys no course has instead of dropping them", () => {
    const p: Progress = { solved: { "gone-problem": "good" }, opened: {}, questions: { "99-x/0/0": "later" }, predictions: {}, choices: {} };
    expect(progressByCourse(p, course.courses, course.units).unmapped).toEqual(["questions/99-x/0/0", "solved/gone-problem"]);
  });
});
