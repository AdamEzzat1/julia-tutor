// The front door (docs/COURSES_PLAN.md, Phase 3): every course has a landing
// page, the navigation and the README name each course's status as its
// manifest does, estimates say they are estimates, and the claims the review
// removed stay removed. Files are read as text through Vite's ?raw imports.
import { describe, expect, it } from "vitest";
import quarto from "../../site/_quarto.yml?raw";
import readme from "../../README.md?raw";
import { course, crossPrerequisites, estimateText, statusNote } from "./course";

const pages = import.meta.glob("../../site/*.qmd", { query: "?raw", import: "default", eager: true }) as Record<string, string>;
const views = import.meta.glob("./views/*.tsx", { query: "?raw", import: "default", eager: true }) as Record<string, string>;
const page = (name: string) => pages[`../../site/${name}`];

describe("course landing pages", () => {
  it("one page per course, mounting its own course, titled as the manifest", () => {
    const landing = Object.keys(pages).filter((p) => /\/course-[^/]+\.qmd$/.test(p)).sort();
    expect(landing).toEqual(course.courses.map((c) => `../../site/course-${c.id}.qmd`).sort());
    for (const c of course.courses) {
      const src = page(`course-${c.id}.qmd`);
      expect(src).toContain(`data-view="course-landing" data-course="${c.id}"`);
      expect(src).toContain(`title: "${c.title}"`);
    }
  });

  it("estimates are ranges from counts and always labelled as estimates", () => {
    for (const c of course.courses) {
      expect(c.estimate.low_hours).toBeGreaterThan(0);
      expect(c.estimate.high_hours).toBeGreaterThan(c.estimate.low_hours);
      expect(c.estimate.basis).toMatch(/not measured$/);
      expect(estimateText(c)).toMatch(/\(estimate\)$/);
    }
  });

  it("a shown download size names where it was measured", () => {
    for (const c of course.courses.filter((x) => x.status !== "planned")) {
      expect(c.setup.download, c.id).not.toBe("");
      expect(c.setup.measured, c.id).toMatch(/CI run \d+/);
    }
  });

  it("units needed from other courses come from courses this one requires", () => {
    for (const c of course.courses)
      for (const g of crossPrerequisites(c)) expect(c.requires, `${c.id} needs ${g.course.id}`).toContain(g.course.id);
    const scicomp = course.courses.find((c) => c.id === "scicomp")!;
    expect(crossPrerequisites(scicomp).length).toBeGreaterThan(0);
    expect(crossPrerequisites(course.courses.find((c) => c.id === "core")!)).toEqual([]);
  });
});

describe("course status is said everywhere", () => {
  it("navigation labels carry the status of a course that is not ready", () => {
    for (const c of course.courses) {
      const m = new RegExp(`href: course-${c.id}\\.qmd\\s*\\n\\s*text: "([^"]+)"`).exec(quarto);
      expect(m, `nav entry for ${c.id}`).not.toBeNull();
      expect(m![1]).toBe(statusNote(c) ? `${c.title} (${statusNote(c)})` : c.title);
    }
  });

  it("the README's course table matches the manifests", () => {
    for (const c of course.courses) {
      const row = readme.split("\n").find((l) => l.startsWith(`| ${c.title} |`));
      expect(row, c.id).toBeDefined();
      const status = row!.split("|").map((s) => s.trim()).filter(Boolean).pop()!.replace(/\*/g, "");
      expect(status).toBe(c.status === "in-progress" ? "in progress" : c.status);
    }
  });

  it("a course that is not ready says why", () => {
    for (const c of course.courses) expect(c.status_note === "", c.id).toBe(c.status === "ready");
  });

  it("views that list courses show the status note", () => {
    for (const v of ["Hero.tsx", "CourseLanding.tsx", "Course.tsx", "Cases.tsx"]) expect(views[`./views/${v}`], v).toContain("statusNote(");
  });
});

describe("claims the review removed stay removed", () => {
  const sources = { ...pages, ...views, README: readme };
  it.each([
    ["research-grade", /research[- ]grade/i],
    ["an outcome claimed for spaced review", /keeps it fixed/i],
    ["feedback called trustworthy", /trustworthy/i],
  ])("no %s", (_, re) => {
    for (const [name, text] of Object.entries(sources)) expect(re.test(text), name).toBe(false);
  });

  it("the homepage's counts are labelled as counts of what was built", () => {
    expect(views["./views/Hero.tsx"]).toContain("counts of what was built, not of what learners learned");
    expect(views["./views/Hero.tsx"]).toContain("Learner outcomes: none measured yet");
  });
});
