// Reviews due: an SM-2 queue built from the course questions a learner missed.
//
// What enters: a concept question not answered on the first pick (progress
// "later"), and a prediction (choice or typed) committed and missed. A
// prediction shown without predicting (pick 0) is not a miss and stays out.
//
// Scheduling is models.ts's sm2Update, which mirrors src/models.jl. A miss is
// a lapse (quality 2: repetitions reset, interval 1 day, easiness down). A
// review is one pick, scored once, like a prediction: recalled = quality 5,
// missed = quality 2. A miss seen live is due tomorrow (the lapse interval);
// a miss found in progress saved before this queue existed has no date, so it
// is due today.
//
// Keys reuse the progress keys with a kind prefix: `q:<unit>/<section>/<question>`
// and `p:<unit>/<section>/<example>`. A key that no longer resolves (a unit was
// rewritten) is reported as stale and never shown; it is kept, not dropped.
// Stored per browser (`julia-tutor/reviews/v1`), guarded like progress.ts.
import type { Example, Prediction, Question, Unit } from "./course";
import { sm2Due, sm2Initial, sm2Update, type SM2State } from "./models";
import type { Progress } from "./progress";

export interface ReviewItem extends SM2State {
  /** ISO date the item is next due */
  due: string;
  /** reviews done (the miss that seeded it is not one) */
  reviews: number;
}
export type Reviews = Record<string, ReviewItem>;

export const LAPSE = 2;
export const RECALLED = 5;

export type Card =
  | { key: string; kind: "question"; unit: Unit; q: Question }
  | { key: string; kind: "prediction"; unit: Unit; ex: Example; p: Prediction };

export const questionReviewKey = (progressKey: string) => `q:${progressKey}`;
export const predictionReviewKey = (progressKey: string) => `p:${progressKey}`;

/** The progress keys a learner missed, as review keys, sorted. */
export function missedKeys(p: Progress): string[] {
  const out: string[] = [];
  for (const [k, v] of Object.entries(p.questions)) if (v === "later") out.push(questionReviewKey(k));
  for (const [k, r] of Object.entries(p.predictions)) if (r.pick > 0 && !r.hit) out.push(predictionReviewKey(k));
  return out.sort();
}

const lapsed = (due: string): ReviewItem => ({ ...sm2Update(sm2Initial(), LAPSE), due, reviews: 0 });

/** A miss seen now: due after the lapse interval (tomorrow). An item already queued is left as it is. */
export function addMiss(r: Reviews, key: string, today: string): Reviews {
  if (r[key]) return r;
  const s = sm2Update(sm2Initial(), LAPSE);
  return { ...r, [key]: { ...s, due: sm2Due(s, today), reviews: 0 } };
}

/** Queue every miss in saved progress that is not queued yet, due today (its date is unknown). */
export function seed(r: Reviews, p: Progress, today: string): Reviews {
  const missing = missedKeys(p).filter((k) => !r[k]);
  if (!missing.length) return r;
  const next = { ...r };
  for (const k of missing) next[k] = lapsed(today);
  return next;
}

/** Score one review: recalled (quality 5) or missed (quality 2), and schedule the next. */
export function settleReview(r: Reviews, key: string, recalled: boolean, today: string): Reviews {
  const prev = r[key] ?? lapsed(today);
  const s = sm2Update(prev, recalled ? RECALLED : LAPSE);
  return { ...r, [key]: { ...s, due: sm2Due(s, today), reviews: prev.reviews + 1 } };
}

/** The question or prediction a key names, or null if the course no longer has it (or cannot show it). */
export function resolve(key: string, units: Unit[]): Card | null {
  const m = /^([qp]):([^/]+)\/(\d+)\/(\d+)$/.exec(key);
  if (!m) return null;
  const unit = units.find((u) => u.id === m[2]);
  const sec = unit?.sections[+m[3]];
  if (!unit || !sec) return null;
  if (m[1] === "q") {
    const q = sec.questions[+m[4]];
    // an error question is only shown with its recorded message
    if (!q || (q.kind === "error" && (q.output ?? null) === null)) return null;
    return { key, kind: "question", unit, q };
  }
  const ex = sec.examples[+m[4]];
  if (!ex?.predict) return null;
  return { key, kind: "prediction", unit, ex, p: ex.predict };
}

/** Cards due on or before `today` among `units`, earliest due first; keys that do not resolve are stale. */
export function dueCards(r: Reviews, units: Unit[], today: string): { cards: Card[]; stale: string[] } {
  const cards: Card[] = [];
  const stale: string[] = [];
  const unitIds = new Set(units.map((u) => u.id));
  const keys = Object.keys(r).filter((k) => r[k].due <= today)
    .sort((a, b) => (r[a].due < r[b].due ? -1 : r[a].due > r[b].due ? 1 : a < b ? -1 : a > b ? 1 : 0));
  for (const k of keys) {
    const unitId = /^[qp]:([^/]+)\//.exec(k)?.[1];
    if (unitId && !unitIds.has(unitId)) continue; // another course's item: not this list's to show or call stale
    const c = resolve(k, units);
    if (c) cards.push(c); else stale.push(k);
  }
  return { cards, stale };
}

/** The next date anything is due after today (among `units`' items when given), or null. */
export function nextDue(r: Reviews, today: string, units?: Unit[]): string | null {
  const ids = units ? new Set(units.map((u) => u.id)) : null;
  let best: string | null = null;
  for (const [k, v] of Object.entries(r)) {
    if (ids && !ids.has(/^[qp]:([^/]+)\//.exec(k)?.[1] ?? "")) continue;
    if (v.due > today && (best === null || v.due < best)) best = v.due;
  }
  return best;
}

const KEY = "julia-tutor/reviews/v1";

export function loadReviews(): Reviews {
  try {
    const raw = window.localStorage.getItem(KEY);
    return raw ? (JSON.parse(raw) as Reviews) : {};
  } catch {
    return {};
  }
}

export function saveReviews(r: Reviews): Reviews {
  try {
    window.localStorage.setItem(KEY, JSON.stringify(r));
  } catch {
    /* reviews last for this page view */
  }
  return r;
}
