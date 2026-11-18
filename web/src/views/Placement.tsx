// Placement check (placement.ts): a course's predict-the-output items, one pick
// each, scored once, then which units the answers suggest skipping. Answers are
// saved as they are given, so the check can be left and resumed.
import { useState } from "react";
import { Code } from "../components/Code";
import { Markdown, md } from "../components/Markdown";
import { course, unitNumber, type Unit } from "../course";
import { checkItems, verdicts, type CheckItem, type PlacementAnswers, type Verdict } from "../placement";

const LETTERS = "ABCDEF";

export function PlacementPanel({ units, answers, onAnswer, onRetake, go }: {
  units: Unit[]; answers: PlacementAnswers;
  onAnswer: (key: string, pick: number) => void; onRetake: () => void; go: (unit: string) => void;
}) {
  const items = checkItems(units);
  const [open, setOpen] = useState(false);
  // the item on screen: stays after its pick until "Next", so the answer can be read
  const [at, setAt] = useState<string | null>(null);
  if (!items.length) return null;

  const answered = items.filter((c) => answers[c.key]);
  const nextKey = items.find((c) => !answers[c.key])?.key ?? null;
  const current = items.find((c) => c.key === (at ?? nextKey)) ?? null;

  if (open && current) {
    return (
      <section className="jt-panel jt-review" aria-label="Placement check">
        <div className="jt-row" style={{ justifyContent: "space-between", alignItems: "baseline" }}>
          <div className="jt-eyebrow">Placement check · {items.indexOf(current) + 1} of {items.length} · one pick, scored once</div>
          <button className="jt-btn ghost jt-small" onClick={() => { setOpen(false); setAt(null); }}>Stop (answers are kept)</button>
        </div>
        <PlacementCard key={current.key} c={current} answer={answers[current.key] ?? null}
          onPick={(p) => { setAt(current.key); onAnswer(current.key, p); }}
          onNext={() => setAt(null)} last={!items.some((c) => c.key !== current.key && !answers[c.key])} />
      </section>
    );
  }

  const done = answered.length === items.length;
  const v = verdicts(units, answers);
  const ready = units.filter((u) => u.status === "ready");
  const by = (k: Verdict) => ready.filter((u) => v[u.id] === k);
  return (
    <section className="jt-panel jt-review" aria-label="Placement check">
      <div className="jt-eyebrow">Placement check · {items.length} predict-the-output questions</div>
      {answered.length === 0 ? (
        <div className="jt-row" style={{ alignItems: "center" }}>
          <p style={{ margin: 0, maxWidth: "46rem" }}>
            Already know some Julia? Predict what {items.length} short snippets print, one pick each. A unit is
            suggested for skipping only when every question about it is right. The check covers{" "}
            {ready.length - by("unchecked").length} of this course's {ready.length} units; it says nothing about the rest.
          </p>
          <button className="jt-btn" onClick={() => { setOpen(true); setAt(null); }}>Start the check</button>
        </div>
      ) : (
        <>
          <p style={{ margin: "0.2rem 0 0.5rem" }}>
            {answered.filter((c) => answers[c.key].right).length} of {answered.length} right
            {done ? "" : ` · ${items.length - answered.length} still to answer`}. Every answer was read from the
            output recorded on Julia {course.julia}.
          </p>
          <PlacementResult title="You can skip" units={by("skip")} go={go}
            note="Every question about these was right. Skim the summary, or try a practice problem to be sure." />
          <PlacementResult title="Study" units={by("study")} go={go}
            note="A question about each of these was missed." />
          {!done && <PlacementResult title="Not answered yet" units={by("pending")} go={go} note="" />}
          <PlacementResult title="Not checked" units={by("unchecked")} go={go}
            note="No placement question covers these; read them or try their problems." />
          <div className="jt-row" style={{ marginTop: "0.5rem" }}>
            {!done && <button className="jt-btn" onClick={() => { setOpen(true); setAt(null); }}>Continue the check</button>}
            <button className="jt-btn ghost" onClick={() => { onRetake(); setAt(null); setOpen(true); }}>Retake</button>
          </div>
        </>
      )}
    </section>
  );
}

function PlacementResult({ title, units, note, go }: { title: string; units: Unit[]; note: string; go: (u: string) => void }) {
  if (!units.length) return null;
  return (
    <div style={{ margin: "0.4rem 0" }}>
      <div className="jt-small"><strong>{title}</strong>{note ? <span className="jt-muted"> · {note}</span> : null}</div>
      <div className="jt-chips" style={{ marginTop: "0.25rem" }}>
        {units.map((u) => (
          <button key={u.id} className="jt-chip jt-chipbtn" onClick={() => go(u.id)}>
            {unitNumber(u.id)} · {u.title.split(/:\s/)[0]}
          </button>
        ))}
      </div>
    </div>
  );
}

function PlacementCard({ c, answer, onPick, onNext, last }: {
  c: CheckItem; answer: { pick: number; right: boolean } | null; onPick: (pick: number) => void; onNext: () => void; last: boolean;
}) {
  const p = c.item;
  const settled = answer !== null;
  const covered = p.covers.map((id) => unitNumber(id)).join(", ");
  return (
    <div className="jt-question" aria-live="polite">
      <div className="jt-small jt-muted">About unit{p.covers.length === 1 ? "" : "s"} {covered}</div>
      <div className="jt-question-prompt"><Markdown text={p.prompt} /></div>
      <Code src={p.code} />
      <div className="jt-options" role="group" aria-label="Answer options">
        {p.choices.map((t, k) => {
          const i = k + 1;
          const cls = settled && i === p.answer ? "right" : settled && i === answer.pick ? "wrong" : "";
          return (
            <button key={i} className={`jt-option ${cls}`} disabled={settled} onClick={() => onPick(i)}>
              <span className="letter">{LETTERS[k]}</span>
              <code className="jt-option-code">{t}</code>
            </button>
          );
        })}
      </div>
      {settled && <pre className="jt-output" aria-label="Recorded output">{p.output}</pre>}
      {settled && (
        <div className={`jt-callout ${answer.right ? "ok" : "mis"}`}>
          <span className="tag">{answer.right ? "Right" : `Answer ${LETTERS[p.answer - 1]}`}</span>
          <div>
            {!answer.right && p.misconceptions[answer.pick - 1] && (
              <div style={{ marginBottom: "0.3rem" }}>{md(p.misconceptions[answer.pick - 1])}</div>
            )}
            <div>{md(p.explain)}</div>
          </div>
        </div>
      )}
      {settled && <div className="jt-row"><button className="jt-btn" onClick={onNext}>{last ? "See the results" : "Next"}</button></div>}
    </div>
  );
}
