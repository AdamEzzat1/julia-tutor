// Placement check: a short predict-the-output check per course that says which
// units a learner can skip.
//
// Items live in their unit (`[[placement]]` in the unit's TOML, an `output`
// question whose key `tutor course verify` checks against the recorded
// output). A course's check is its units' items in course order. Each item is
// one pick, scored once, like a prediction. Each item covers its own unit and
// may cover earlier units of the course; per unit:
//   skip       every item covering it was answered right
//   study      an item covering it was answered wrong
//   unchecked  no item covers it (the check says nothing about it)
//   pending    items cover it, none was missed, and some are not answered yet
// A miss outweighs any number of hits: suggesting a skip costs more when wrong.
// Answers are stored per browser (`julia-tutor/placement/v1`), guarded like
// progress.ts; retaking a course's check clears that course's answers only.
import type { PlacementItem, Unit } from "./course";

export interface PlacementAnswer {
  pick: number; // 1-based
  right: boolean;
}
/** keyed `<unit>/<item index>` */
export type PlacementAnswers = Record<string, PlacementAnswer>;

export type Verdict = "skip" | "study" | "unchecked" | "pending";

export interface CheckItem {
  key: string;
  unit: Unit;
  item: PlacementItem;
}

/** A course's placement items, in the order of `units` (the course's own order). */
export function checkItems(units: Unit[]): CheckItem[] {
  return units.flatMap((u) => (u.placement ?? []).map((item, i) => ({ key: `${u.id}/${i}`, unit: u, item })));
}

/** Score one pick. */
export const settlePlacement = (item: PlacementItem, pick: number): PlacementAnswer => ({ pick, right: pick === item.answer });

/** The verdict for each unit in `units`, from the answers so far. */
export function verdicts(units: Unit[], answers: PlacementAnswers): Record<string, Verdict> {
  const items = checkItems(units);
  const out: Record<string, Verdict> = {};
  for (const u of units) {
    const covering = items.filter((c) => c.item.covers.includes(u.id));
    if (!covering.length) out[u.id] = "unchecked";
    else if (covering.some((c) => answers[c.key] && !answers[c.key].right)) out[u.id] = "study";
    else if (covering.every((c) => answers[c.key]?.right)) out[u.id] = "skip";
    else out[u.id] = "pending";
  }
  return out;
}

/** The answers with this course's items removed (to retake its check). */
export function clearCourse(answers: PlacementAnswers, units: Unit[]): PlacementAnswers {
  const keys = new Set(checkItems(units).map((c) => c.key));
  return Object.fromEntries(Object.entries(answers).filter(([k]) => !keys.has(k)));
}

const KEY = "julia-tutor/placement/v1";

export function loadPlacement(): PlacementAnswers {
  try {
    const raw = window.localStorage.getItem(KEY);
    return raw ? (JSON.parse(raw) as PlacementAnswers) : {};
  } catch {
    return {};
  }
}

export function savePlacement(a: PlacementAnswers): PlacementAnswers {
  try {
    window.localStorage.setItem(KEY, JSON.stringify(a));
  } catch {
    /* answers last for this page view */
  }
  return a;
}
