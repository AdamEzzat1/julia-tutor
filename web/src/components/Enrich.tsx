import { Markdown, md } from "./Markdown";
import { citeLabel, refNumber, type Analogy, type Diagram, type Reference } from "../enrich";

// Analogies, diagrams and citations around a section's prose. An analogy
// always shows where it stops matching the mathematics; a diagram is an <img>
// of a checked SVG (never inlined); a citation links to its entry in the
// unit's reference list.

export function DiagramView({ d }: { d: Diagram }) {
  return (
    <figure className="jt-diagram">
      <img src={d.src} alt={d.alt} loading="lazy" />
      {d.caption && <figcaption className="jt-small jt-muted">{md(d.caption)}</figcaption>}
    </figure>
  );
}

export function AnalogyView({ a }: { a: Analogy }) {
  return (
    <aside className="jt-callout analogy" aria-label={`Analogy: ${a.title}`}>
      <span className="tag">Analogy</span>
      <div>
        {a.title && <strong>{a.title}</strong>}
        <Markdown text={a.text} />
        <div className="jt-analogy-breaks">
          <span className="jt-eyebrow">Where the analogy breaks down</span>
          <Markdown text={a.breaks} />
        </div>
      </div>
    </aside>
  );
}

export function SectionSources({ refs, all, unitId }: { refs: string[]; all: Reference[]; unitId: string }) {
  const shown = refs.map((id) => ({ id, n: refNumber(all, id), r: all.find((x) => x.id === id) }))
    .filter((x) => x.r !== undefined);
  if (shown.length === 0) return null;
  return (
    <p className="jt-small jt-sources">
      <span className="jt-muted">Sources: </span>
      {shown.map((x, i) => (
        <span key={x.id}>
          {i > 0 && "; "}
          <a href={`#ref-${unitId}-${x.id}`}>[{x.n}] {citeLabel(x.r!)}</a>
        </span>
      ))}
    </p>
  );
}

export function ReferenceList({ refs, unitId }: { refs: Reference[]; unitId: string }) {
  if (refs.length === 0) return null;
  return (
    <section className="jt-panel jt-pad" aria-labelledby={`jt-refs-${unitId}`}>
      <div className="jt-eyebrow">Further reading</div>
      <h3 id={`jt-refs-${unitId}`} style={{ marginTop: "0.2rem" }}>Papers and sources cited in this unit</h3>
      <p className="jt-small jt-muted">
        Public links. Each entry says what in the unit it supports; reading the source is optional, but it is
        where the claims come from.
      </p>
      <ol className="jt-refs">
        {refs.map((r) => (
          <li key={r.id} id={`ref-${unitId}-${r.id}`}>
            {r.authors} ({r.year}). <a href={r.url} target="_blank" rel="noreferrer">{r.title}</a>. <em>{r.venue}</em>.
            <div className="jt-small jt-muted">{md(r.note)}</div>
          </li>
        ))}
      </ol>
    </section>
  );
}
