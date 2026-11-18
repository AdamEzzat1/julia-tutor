// Reviews due (review.ts): the missed questions and predictions whose SM-2
// date has come, asked again one at a time. One pick, scored once, then the
// answer, the explanation and (for a prediction) the recorded output.
import { useState } from "react";
import { Code } from "../components/Code";
import { Markdown, md } from "../components/Markdown";
import { course, unitNumber, type Unit } from "../course";
import { parseTyped, toleranceText, withinTolerance } from "../predict";
import { resolve, type Card } from "../review";

const LETTERS = "ABCDEF";

export function ReviewPanel({ cards, stale, next, units, onSettle, go }: {
  cards: Card[]; stale: number; next: string | null; units: Unit[];
  /** score a review; returns the date it is next due */
  onSettle: (key: string, recalled: boolean) => string; go: (unit: string) => void;
}) {
  // The session works from the keys due when it started: settling a card reschedules it,
  // and it must stay on screen until the learner moves on.
  const [session, setSession] = useState<string[] | null>(null);
  const [at, setAt] = useState(0);
  const [score, setScore] = useState(0);

  if (session === null) {
    return (
      <section className="jt-panel jt-review" aria-label="Reviews due">
        <div className="jt-eyebrow">Reviews due · spaced repetition (SM-2)</div>
        {cards.length > 0 ? (
          <div className="jt-row" style={{ alignItems: "center" }}>
            <p style={{ margin: 0 }}>
              <strong>{cards.length}</strong> question{cards.length === 1 ? "" : "s"} you missed {cards.length === 1 ? "is" : "are"} due
              for review. Each comes back after 1 day, then 6, then longer while you keep getting it right.
            </p>
            <button className="jt-btn" onClick={() => { setSession(cards.map((c) => c.key)); setAt(0); setScore(0); }}>
              Start review
            </button>
          </div>
        ) : (
          <p className="jt-small jt-muted" style={{ margin: 0 }}>
            Nothing due. A question you miss here comes back for review the next day{next ? `; the next one is due ${next}` : ""}.
          </p>
        )}
        {stale > 0 && (
          <p className="jt-small jt-muted" style={{ margin: "0.4rem 0 0" }}>
            {stale} queued review{stale === 1 ? " points" : "s point"} at a question the course no longer has; {stale === 1 ? "it is" : "they are"} not shown.
          </p>
        )}
      </section>
    );
  }

  const done = at >= session.length;
  const card = done ? null : resolve(session[at], units);
  return (
    <section className="jt-panel jt-review" aria-label="Review session">
      <div className="jt-row" style={{ justifyContent: "space-between", alignItems: "baseline" }}>
        <div className="jt-eyebrow">Review · {done ? "done" : `${at + 1} of ${session.length}`}</div>
        <button className="jt-btn ghost jt-small" onClick={() => setSession(null)}>{done ? "Close" : "Stop"}</button>
      </div>
      {done ? (
        <p style={{ margin: "0.4rem 0 0" }}>
          {score} of {session.length} recalled. The ones you got come back later; the ones you missed come back tomorrow.
        </p>
      ) : card ? (
        <ReviewCard key={card.key} card={card} go={go}
          onSettle={(ok) => { if (ok) setScore((s) => s + 1); return onSettle(card.key, ok); }}
          onNext={() => setAt((i) => i + 1)} />
      ) : (
        // the course data changed under the session: skip it
        <button className="jt-btn" onClick={() => setAt((i) => i + 1)}>Skip (no longer in the course)</button>
      )}
    </section>
  );
}

function ReviewCard({ card, onSettle, onNext, go }: {
  card: Card; onSettle: (recalled: boolean) => string; onNext: () => void; go: (unit: string) => void;
}) {
  const [pick, setPick] = useState<number | null>(null);
  const [text, setText] = useState("");
  const [typed, setTyped] = useState<number | null>(null);
  const [due, setDue] = useState("");
  const typedP = card.kind === "prediction" && card.p.typed ? card.p.typed : null;
  const answer = card.kind === "question" ? card.q.answer : card.p.answer;
  const choices = card.kind === "question" ? card.q.choices : card.p.choices;
  const settled = typedP ? typed !== null : pick !== null;
  const right = typedP ? typed !== null && withinTolerance(typedP, typed) : pick === answer;
  const x = parseTyped(text);

  const choose = (i: number) => { if (settled) return; setPick(i); setDue(onSettle(i === answer)); };
  const commitTyped = () => { if (settled || x === null || !typedP) return; setTyped(x); setDue(onSettle(withinTolerance(typedP, x))); };

  const prompt = card.kind === "question" ? card.q.prompt : card.p.prompt;
  const code = card.kind === "question" ? card.q.code : card.ex.code;
  const asOutput = card.kind === "prediction" || card.q.kind === "output";
  return (
    <div className="jt-question" aria-live="polite">
      <div className="jt-small jt-muted">
        From <button className="jt-inlinelink" onClick={() => go(card.unit.id)}>unit {unitNumber(card.unit.id)} · {card.unit.title.split(/:\s/)[0]}</button>
        {" · "}{card.kind === "question" ? (card.q.kind === "error" ? "read the error" : card.q.kind === "output" ? "predict the output" : "concept question")
          : typedP ? `estimate, ${toleranceText(typedP)}` : "predict, then run"}
      </div>
      <div className="jt-question-prompt"><Markdown text={prompt} /></div>
      {code && <Code src={code} />}
      {card.kind === "question" && card.q.kind === "error" && card.q.output && (
        <pre className="jt-output err" aria-label="The message Julia printed">{card.q.output}</pre>
      )}
      {typedP ? (
        <div className="jt-row">
          <label className="jt-small">
            Your number{typedP.unit ? ` (${typedP.unit})` : ""}
            <input className="jt-input" style={{ display: "block", marginTop: "0.3rem", width: "12rem" }} inputMode="decimal"
              value={text} disabled={settled} onChange={(e) => setText(e.target.value)}
              onKeyDown={(e) => { if (e.key === "Enter") commitTyped(); }} />
          </label>
          <button className="jt-btn" disabled={settled || x === null} onClick={commitTyped}>Commit</button>
          {!settled && text.trim() !== "" && x === null && <span className="jt-small jt-muted">A number, like 4, 0.25 or 1e-6.</span>}
        </div>
      ) : (
        <div className="jt-options" role="group" aria-label="Answer options">
          {choices.map((c, k) => {
            const i = k + 1;
            const cls = settled && i === answer ? "right" : settled && i === pick ? "wrong" : "";
            return (
              <button key={i} className={`jt-option ${cls}`} disabled={settled} onClick={() => choose(i)}>
                <span className="letter">{LETTERS[k]}</span>
                {asOutput ? <code className="jt-option-code">{c}</code> : <span>{md(c)}</span>}
              </button>
            );
          })}
        </div>
      )}
      {settled && card.kind === "prediction" && card.ex.output !== null && (
        <pre className={`jt-output ${card.ex.ok ? "" : "err"}`} aria-label="Recorded output">{card.ex.output || "(no output)"}</pre>
      )}
      {settled && (
        <div className={`jt-callout ${right ? "ok" : "mis"}`}>
          <span className="tag">{right ? "Recalled" : typedP ? "Not within the tolerance" : `Answer ${LETTERS[answer - 1]}`}</span>
          <div>
            {!right && card.kind === "question" && pick !== null && card.q.misconceptions[pick - 1] && (
              <div style={{ marginBottom: "0.3rem" }}>{md(card.q.misconceptions[pick - 1])}</div>
            )}
            {card.kind === "prediction" && (
              <div className="jt-small">
                {typed !== null && <>You typed <code>{typed}</code>. </>}Measured in the recorded output: <code>{card.p.measured}</code>
                {typedP?.unit ? ` ${typedP.unit}` : ""}.
              </div>
            )}
            <div style={{ marginTop: "0.3rem" }}>{md(card.kind === "question" ? card.q.explain : card.p.explain)}</div>
            <div className="jt-small jt-muted" style={{ marginTop: "0.3rem" }}>
              Next review: {due}{right ? " (the gap grows each time you recall it)" : " (a miss starts the gaps over)"}.
              {card.kind === "prediction" || card.q.kind !== "choice" ? ` Recorded on Julia ${course.julia}.` : ""}
            </div>
          </div>
        </div>
      )}
      {settled && <div className="jt-row"><button className="jt-btn" onClick={onNext}>Next</button></div>}
    </div>
  );
}
