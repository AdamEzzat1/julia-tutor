// Types and pure helpers for a unit's analogies, diagrams and references
// (exported by `tutor site-data`; validated by Course.enrichment_problems).

export interface Analogy {
  title: string;
  text: string;
  /** where the analogy stops matching the mathematics (always present) */
  breaks: string;
}

export interface Diagram {
  /** site path: assets/diagrams/<unit>/<file>.svg */
  src: string;
  alt: string;
  caption: string;
}

export interface Reference {
  id: string;
  authors: string;
  title: string;
  venue: string;
  year: number;
  url: string;
  /** what in the unit this source supports */
  note: string;
}

/** 1-based position of a reference in the unit's list (0 if absent). */
export function refNumber(all: Reference[], id: string): number {
  return all.findIndex((r) => r.id === id) + 1;
}

/** "Raissi et al. 2019" from "Raissi, M.; Perdikaris, P.; Karniadakis, G. E.". */
export function citeLabel(r: Reference): string {
  const people = r.authors.split(";").map((s) => s.trim()).filter(Boolean);
  const surname = (p: string) => p.split(",")[0].trim();
  if (people.length === 0) return String(r.year);
  if (people.length === 1) return `${surname(people[0])} ${r.year}`;
  if (people.length === 2) return `${surname(people[0])} and ${surname(people[1])} ${r.year}`;
  return `${surname(people[0])} et al. ${r.year}`;
}
