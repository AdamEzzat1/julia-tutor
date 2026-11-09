// Course progress in this browser: which problems are solved (and the best
// performance verdict reached) and which units were opened. Guarded like
// storage.ts: the site works without storage.

export type Overall = "excellent" | "good" | "needs-work";

export interface Progress {
  solved: Record<string, Overall>;
  opened: Record<string, boolean>;
  /** concept questions by `<unit>/<section>/<question>`: right on the first pick, or later */
  questions: Record<string, "first-try" | "later">;
}

const KEY = "julia-tutor/course/v1";

export function loadProgress(): Progress {
  try {
    const raw = window.localStorage.getItem(KEY);
    const p = raw ? (JSON.parse(raw) as Partial<Progress>) : {};
    return { solved: p.solved ?? {}, opened: p.opened ?? {}, questions: p.questions ?? {} };
  } catch {
    return { solved: {}, opened: {}, questions: {} };
  }
}

export function saveProgress(p: Progress): Progress {
  try {
    window.localStorage.setItem(KEY, JSON.stringify(p));
  } catch {
    /* progress lasts for this page view */
  }
  return p;
}
