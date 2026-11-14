// Course progress in this browser: which problems are solved (and the best
// performance verdict reached) and which units were opened. Guarded like
// storage.ts: the site works without storage.
import type { PredictionRecord } from "./predict";
import type { ChoiceRecord } from "./choose";
import type { BreakRecord } from "./breakit";
import type { BugRecord } from "./findbug";
import type { ParsonsRecord } from "./parsons";

export type Overall = "excellent" | "good" | "needs-work";

export interface Progress {
  solved: Record<string, Overall>;
  opened: Record<string, boolean>;
  /** concept questions by `<unit>/<section>/<question>`: right on the first pick, or later */
  questions: Record<string, "first-try" | "later">;
  /** predictions by `<unit>/<section>/<example>`: the one committed pick (predict.ts) */
  predictions: Record<string, PredictionRecord>;
  /** method choices by `<unit>/<section>/<example>`: the one committed pick and its reason (choose.ts) */
  choices: Record<string, ChoiceRecord>;
  /** break-it challenges by `<unit>/<section>/<example>`: the one committed edge (breakit.ts) */
  breaks: Record<string, BreakRecord>;
  /** find-the-bug problems by problem id: test runs, hints, fixed (findbug.ts) */
  bugs: Record<string, BugRecord>;
  /** Parsons problems by problem id: checks before solving, solved, first try (parsons.ts) */
  parsons: Record<string, ParsonsRecord>;
}

const KEY = "julia-tutor/course/v1";

export function loadProgress(): Progress {
  try {
    const raw = window.localStorage.getItem(KEY);
    const p = raw ? (JSON.parse(raw) as Partial<Progress>) : {};
    return { solved: p.solved ?? {}, opened: p.opened ?? {}, questions: p.questions ?? {},
             predictions: p.predictions ?? {}, choices: p.choices ?? {}, breaks: p.breaks ?? {}, bugs: p.bugs ?? {},
             parsons: p.parsons ?? {} };
  } catch {
    return { solved: {}, opened: {}, questions: {}, predictions: {}, choices: {}, breaks: {}, bugs: {}, parsons: {} };
  }
}

/**
 * Progress per course, from the stored keys. Nothing in `julia-tutor/course/v1`
 * is keyed by course (problems by problem id, units by unit id, questions by
 * `<unit>/...`), and unit and problem ids did not change in the course split,
 * so progress saved before it needs no rewrite: this maps it. Keys that no
 * course has (a removed problem, say) are returned, never dropped silently.
 */
export function progressByCourse(
  p: Progress,
  courses: { id: string; units: string[] }[],
  units: { id: string; problems: { id: string }[] }[],
): { byCourse: Record<string, CourseCounts>; unmapped: string[] } {
  const unitCourse = new Map<string, string>();
  for (const c of courses) for (const u of c.units) unitCourse.set(u, c.id);
  const problemCourse = new Map<string, string>();
  for (const u of units) for (const q of u.problems) {
    const c = unitCourse.get(u.id);
    if (c) problemCourse.set(q.id, c);
  }
  const byCourse: Record<string, CourseCounts> = {};
  for (const c of courses)
    byCourse[c.id] = { solved: 0, opened: 0, questions: 0, predictions: 0, choices: 0, breaks: 0, bugs: 0, parsons: 0 };
  const unmapped: string[] = [];
  const put = (c: string | undefined, field: keyof CourseCounts, key: string) =>
    c ? (byCourse[c][field] += 1) : unmapped.push(`${field}/${key}`);
  for (const k of Object.keys(p.solved)) put(problemCourse.get(k), "solved", k);
  for (const k of Object.keys(p.opened)) put(unitCourse.get(k), "opened", k);
  for (const k of Object.keys(p.questions)) put(unitCourse.get(k.split("/")[0]), "questions", k);
  for (const k of Object.keys(p.predictions ?? {})) put(unitCourse.get(k.split("/")[0]), "predictions", k);
  for (const k of Object.keys(p.choices ?? {})) put(unitCourse.get(k.split("/")[0]), "choices", k);
  for (const k of Object.keys(p.breaks ?? {})) put(unitCourse.get(k.split("/")[0]), "breaks", k);
  for (const k of Object.keys(p.bugs ?? {})) put(problemCourse.get(k), "bugs", k);
  for (const k of Object.keys(p.parsons ?? {})) put(problemCourse.get(k), "parsons", k);
  return { byCourse, unmapped: unmapped.sort() };
}

export interface CourseCounts {
  solved: number; opened: number; questions: number; predictions: number; choices: number; breaks: number; bugs: number;
  parsons: number;
}

export function saveProgress(p: Progress): Progress {
  try {
    window.localStorage.setItem(KEY, JSON.stringify(p));
  } catch {
    /* progress lasts for this page view */
  }
  return p;
}
