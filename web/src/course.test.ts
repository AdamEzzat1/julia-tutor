import { describe, expect, it } from "vitest";
import { parseBlocks } from "./components/Markdown";
import { course, questionState, type Question } from "./course";
import { parseConnect } from "./server";

const TOKEN = "0123456789abcdef0123456789abcdef0123456789abcdef";

describe("connect fragment", () => {
  it("accepts the link tutor serve prints", () => {
    expect(parseConnect(`#connect=8749.${TOKEN}`)).toEqual({ port: 8749, token: TOKEN });
  });
  it("rejects short, non-hex or uppercase tokens and odd ports", () => {
    expect(parseConnect(`#connect=8749.${TOKEN.slice(1)}`)).toBeNull();
    expect(parseConnect(`#connect=8749.${TOKEN.toUpperCase()}`)).toBeNull();
    expect(parseConnect(`#connect=80.${TOKEN}`)).toBeNull();
    expect(parseConnect(`#connect=99999.${TOKEN}`)).toBeNull();
    expect(parseConnect(`#connect=8749.${TOKEN}x`)).toBeNull();
    expect(parseConnect("#setup")).toBeNull();
  });
});

describe("markdown blocks", () => {
  it("splits paragraphs, fences and lists", () => {
    const b = parseBlocks("One\nline.\n\n```julia\nx = 1\n```\n\n* a\n* b\n  continued\n\n1. first\n2. second");
    expect(b).toEqual([
      { kind: "p", text: "One line." },
      { kind: "code", text: "x = 1" },
      { kind: "ul", items: ["a", "b continued"] },
      { kind: "ol", items: ["first", "second"] },
    ]);
  });
});

describe("course data", () => {
  it("every ready unit has recorded outputs for every example", () => {
    for (const u of course.units.filter((x) => x.status === "ready"))
      for (const s of u.sections)
        for (const e of s.examples) expect(e.output, `${u.id}: ${e.code.slice(0, 40)}`).not.toBeNull();
  });
  it("every problem shows its sample results and never ships a reference", () => {
    for (const u of course.units)
      for (const p of u.problems) {
        expect(p.samples.length, p.id).toBeGreaterThan(0);
        // no key holding the reference, its variants or the generated cases
        // (prompts may mention "the reference" in prose)
        for (const k of ["reference", "variants", "gen"]) expect(p, `${p.id}.${k}`).not.toHaveProperty(k);
      }
  });
  it("planned units have an outline; units are in track order", () => {
    const order = course.tracks;
    let last = 0;
    for (const u of course.units) {
      if (u.status === "planned") expect(u.outline.length, u.id).toBeGreaterThan(0);
      const t = order.indexOf(u.track);
      expect(t, u.id).toBeGreaterThanOrEqual(last);
      last = t;
    }
  });
  it("every non-base environment lists exact package versions", () => {
    for (const [env, pkgs] of Object.entries(course.envs))
      if (env !== "base") for (const p of pkgs) expect(p.version, `${env}/${p.name}`).toMatch(/^\d+\.\d+\.\d+$/);
  });
});

describe("concept questions", () => {
  const q: Question = {
    kind: "choice", prompt: "p", code: "", choices: ["a", "b", "c"], answer: 2, explain: "e",
    misconceptions: ["thinks a", "", "thinks c"],
  };
  it("a right first pick is first-try; wrong picks before the answer are kept", () => {
    expect(questionState(q, [])).toEqual({ done: false, firstTry: false, wrong: [] });
    expect(questionState(q, [2])).toEqual({ done: true, firstTry: true, wrong: [] });
    expect(questionState(q, [3, 1])).toEqual({ done: false, firstTry: false, wrong: [3, 1] });
    expect(questionState(q, [3, 2])).toEqual({ done: true, firstTry: false, wrong: [3] });
  });
  it("every question in the course data has feedback for each wrong choice and a figure path under assets", () => {
    for (const u of course.units)
      for (const s of u.sections) {
        for (const x of s.questions) {
          expect(x.answer, u.id).toBeGreaterThanOrEqual(1);
          x.misconceptions.forEach((m, i) => expect(i + 1 === x.answer ? m === "" : m.length > 0, `${u.id}: ${x.prompt}`).toBe(true));
        }
        for (const e of s.examples) for (const src of e.images) expect(src).toMatch(/^assets\/figures\/[\w-]+\/[\w.-]+\.(png|svg)$/);
      }
  });
});
