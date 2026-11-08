import { useMemo, useState } from "react";
import { Code } from "../components/Code";
import { inline, Prose } from "../components/Prose";
import { data, type Check, type Lesson } from "../data";
import { dueItems, lessonStarted, outcomeOf, settleCheck, type Outcome } from "../lessonLogic";
import { todayISO, useWebState } from "../storage";

const LETTERS = "abcdefgh";

export function LessonsView() {
  const [state, update, reset] = useWebState();
  const [lessonId, setLessonId] = useState(data.lessons[0]?.id ?? "");
  const lesson = data.lessons.find((l) => l.id === lessonId) ?? data.lessons[0];
  const today = todayISO();
  const due = dueItems(state, today);
  const kcs = useMemo(() => [...new Set(data.lessons.flatMap((l) => l.kcs))].sort(), []);

  return (
    <div className="jt-split">
      <div className="jt-grid">
        <nav className="jt-panel jt-nav" aria-label="Lessons">
          {data.lessons.map((l, i) => {
            const missing = l.prerequisites.filter((p) => !lessonStarted(state, p));
            return (
              <button key={l.id} aria-current={l.id === lesson.id} onClick={() => setLessonId(l.id)}>
                <span className="s">L{String(i + 1).padStart(2, "0")} · {l.checks.length} checks
                  {lessonStarted(state, l.id) ? " · started" : ""}</span>
                <span className="t">{l.title.split(":")[0]}</span>
                {missing.length > 0 && <span className="s">builds on {missing.join(", ")}</span>}
              </button>
            );
          })}
        </nav>

        <section className="jt-panel jt-pad" aria-labelledby="jt-mastery">
          <div className="jt-eyebrow" id="jt-mastery">Your model · this browser</div>
          <div className="jt-grid" style={{ gap: "0.7rem", marginTop: "0.7rem" }}>
            {kcs.map((kc) => {
              const p = state.kc[kc];
              return (
                <div className="jt-meter" key={kc}>
                  <div className="row"><span>{kc}</span><b>{p === undefined ? "—" : p.toFixed(2)}</b></div>
                  <div className="bar" aria-hidden="true"><i style={{ width: `${(p ?? 0) * 100}%` }} /></div>
                </div>
              );
            })}
          </div>
          <p className="jt-small jt-muted" style={{ marginTop: "0.8rem" }}>
            P(knows) by Bayesian Knowledge Tracing with prior parameters (not fitted).
            {due.length > 0 ? ` ${due.length} check(s) due for review today (SM-2).` : " No reviews due."}
          </p>
          {Object.keys(state.misconceptions).length > 0 && (
            <div className="jt-chips" style={{ marginBottom: "0.7rem" }}>
              {Object.entries(state.misconceptions).sort().map(([m, n]) => (
                <span key={m} className="jt-chip fail" title="misconception chosen">{m} ×{n}</span>
              ))}
            </div>
          )}
          <button className="jt-btn ghost jt-small" onClick={reset}>Reset my progress</button>
        </section>
      </div>

      <LessonBody key={lesson.id} lesson={lesson} onSettle={(c, a, b) => update((s) => settleCheck(s, lesson, c, a, b, today))} />
    </div>
  );
}

function LessonBody({ lesson, onSettle }: { lesson: Lesson; onSettle: (c: Check, first: number, second: number | null) => void }) {
  const [idx, setIdx] = useState(0);
  const [results, setResults] = useState<(Outcome | null)[]>(() => lesson.checks.map(() => null));
  const check = lesson.checks[idx];
  const [title, subtitle] = lesson.title.split(/:\s*/, 2);

  return (
    <article className="jt-panel jt-pad">
      <div className="jt-toolbar">
        <div className="jt-chips">
          {lesson.kcs.map((k) => <span key={k} className="jt-chip kc">{k}</span>)}
          <span className="jt-chip pass" title="Every answer key was produced by running the snippet">
            ✓ keys verified on Julia {lesson.verified_on}
          </span>
        </div>
        <div className="jt-stepper" aria-label={`Check ${idx + 1} of ${lesson.checks.length}`}>
          {results.map((r, i) => (
            <span key={i} className={i === idx ? "now" : r === "first-try" ? "done-right" : r ? "done-wrong" : ""} />
          ))}
        </div>
      </div>
      <h2>{title}</h2>
      {subtitle && <p className="jt-muted" style={{ fontFamily: "var(--jt-serif)", fontSize: "1.1rem", fontStyle: "italic" }}>{subtitle}</p>}
      <div style={{ maxWidth: "46rem" }}><Prose text={lesson.body} /></div>
      <hr className="jt-divider" />
      <CheckCard
        key={check.id}
        check={check}
        number={idx + 1}
        total={lesson.checks.length}
        onSettle={(first, second) => {
          onSettle(check, first, second);
          setResults((r) => r.map((x, i) => (i === idx ? outcomeOf(check, first, second) : x)));
        }}
        onNext={idx + 1 < lesson.checks.length ? () => setIdx(idx + 1) : undefined}
      />
    </article>
  );
}

type Phase = { kind: "first" } | { kind: "second"; first: number } | { kind: "done"; first: number; second: number | null };

function CheckCard({ check, number, total, onSettle, onNext }: {
  check: Check; number: number; total: number;
  onSettle: (first: number, second: number | null) => void; onNext?: () => void;
}) {
  const [phase, setPhase] = useState<Phase>({ kind: "first" });
  const pick = (i: number) => {
    if (phase.kind === "first") {
      if (i === check.answer) { setPhase({ kind: "done", first: i, second: null }); onSettle(i, null); }
      else setPhase({ kind: "second", first: i });
    } else if (phase.kind === "second") {
      if (i === phase.first) return;
      setPhase({ kind: "done", first: phase.first, second: i });
      onSettle(phase.first, i);
    }
  };
  const first = phase.kind === "first" ? null : phase.first;
  const second = phase.kind === "done" ? phase.second : null;
  const done = phase.kind === "done";
  const mis = (o: number | null) => (o === null ? undefined : check.misconceptions.find((m) => m.option === o));
  const outcome = done ? outcomeOf(check, phase.first, phase.second) : null;

  return (
    <section aria-live="polite">
      <div className="jt-eyebrow">Predict the output · check {number} of {total}</div>
      <h3 style={{ marginTop: "0.35rem" }}>{inline(check.prompt)}</h3>
      <Code src={check.code} />
      <div className="jt-options" role="group" aria-label="Answer options">
        {check.options.map((o, k) => {
          const i = k + 1;
          const cls = done && i === check.answer ? "right"
            : i === first && first !== check.answer ? "wrong"
            : i === second && second !== check.answer ? "wrong" : "";
          return (
            <button key={i} className={`jt-option ${cls}`} disabled={done || i === first} onClick={() => pick(i)}>
              <span className="letter">{LETTERS[k]}</span>
              <span style={{ whiteSpace: "pre-wrap" }}>{o}</span>
            </button>
          );
        })}
      </div>

      {phase.kind !== "first" && first !== check.answer && (
        <>
          {mis(first) && (
            <div className="jt-callout mis"><span className="tag">Not quite</span><div>{inline(mis(first)!.feedback)}
              <div className="jt-small jt-muted" style={{ marginTop: "0.3rem" }}>misconception: <code>{mis(first)!.id}</code></div></div></div>
          )}
          <div className="jt-callout hint"><span className="tag">Hint</span><div>{inline(check.hint)}</div></div>
        </>
      )}
      {phase.kind === "second" && <p className="jt-small jt-muted">One more try. The answer is revealed after a second wrong choice.</p>}

      {done && (
        <>
          {outcome === "revealed" && mis(second) && (
            <div className="jt-callout mis"><span className="tag">Also</span><div>{inline(mis(second)!.feedback)}</div></div>
          )}
          <div className={`jt-callout ${outcome === "revealed" ? "reveal" : "ok"}`}>
            <span className="tag">{outcome === "first-try" ? "Correct" : outcome === "second-try" ? "Second try" : `Answer ${LETTERS[check.answer - 1]})`}</span>
            <div>{inline(check.explanation)}</div>
          </div>
          <div className="jt-toolbar" style={{ marginTop: "0.8rem" }}>
            <span className="jt-small jt-muted">
              Recorded: {outcome === "first-try" ? "correct (SM-2 quality 5)" : outcome === "second-try" ? "after the hint (quality 3)" : "revealed (quality 1)"}
            </span>
            {onNext ? <button className="jt-btn primary" onClick={onNext}>Next check →</button>
              : <span className="jt-chip pass">Lesson complete</span>}
          </div>
        </>
      )}
    </section>
  );
}
