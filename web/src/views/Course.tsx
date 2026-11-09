import { useEffect, useRef, useState } from "react";
import { Code } from "../components/Code";
import { Editor } from "../components/Editor";
import { Feedback } from "../components/Feedback";
import { Markdown, md } from "../components/Markdown";
import { ConnectPanel, Output, RunBox, ServerPill, useDraft } from "../components/Runner";
import {
  course, questionState, TRACK_BLURB, TRACK_LABEL, unitNumber, type Example, type Problem, type Question, type Unit,
} from "../course";
import { loadProgress, saveProgress, type Progress } from "../progress";
import { gradeCode, useServer, type GradeResult } from "../server";

function readParams() {
  const q = new URLSearchParams(window.location.search);
  return { unit: q.get("unit"), problem: q.get("problem") };
}

function writeParams(unit: string | null, problem: string | null) {
  const q = new URLSearchParams();
  if (unit) q.set("unit", unit);
  if (problem) q.set("problem", problem);
  const s = q.toString();
  history.replaceState(null, "", window.location.pathname + (s ? `?${s}` : ""));
}

export function CourseView() {
  const [unitId, setUnitId] = useState<string | null>(() => readParams().unit);
  const [problemId, setProblemId] = useState<string | null>(() => readParams().problem);
  const [progress, setProgress] = useState<Progress>(loadProgress);
  const unit = course.units.find((u) => u.id === unitId) ?? null;
  const top = useRef<HTMLDivElement>(null);

  const go = (u: string | null, p: string | null = null) => {
    setUnitId(u); setProblemId(p); writeParams(u, p);
    if (u) setProgress((s) => saveProgress({ ...s, opened: { ...s.opened, [u]: true } }));
    top.current?.scrollIntoView({ block: "start", behavior: "smooth" });
  };
  const solved = (pid: string, r: GradeResult) =>
    setProgress((s) => {
      const prev = s.solved[pid];
      const rank = { "needs-work": 0, good: 1, excellent: 2 } as const;
      const overall = r.performance?.overall ?? "excellent";
      const best = prev && rank[prev] >= rank[overall] ? prev : overall;
      return saveProgress({ ...s, solved: { ...s.solved, [pid]: best } });
    });
  // The first settlement of a question is the one kept (a reload must not turn "later" into "first-try").
  const answered = (key: string, firstTry: boolean) =>
    setProgress((s) => s.questions[key] ? s :
      saveProgress({ ...s, questions: { ...s.questions, [key]: firstTry ? "first-try" : "later" } }));

  return (
    <div className="jt-split jt-course" ref={top}>
      <nav className="jt-panel jt-nav jt-syllabus" aria-label="Syllabus">
        <button aria-current={unit === null} onClick={() => go(null)}>
          <span className="s">{course.units.filter((u) => u.status === "ready").length} units ready · {course.units.reduce((n, u) => n + u.problems.length, 0)} problems</span>
          <span className="t">Course overview</span>
        </button>
        {course.tracks.map((t) => (
          <div key={t}>
            <div className="jt-eyebrow" style={{ padding: "0.7rem 0.7rem 0.2rem" }}>{TRACK_LABEL[t]}</div>
            {course.units.filter((u) => u.track === t).map((u) => {
              const done = u.problems.filter((p) => progress.solved[p.id]).length;
              return (
                <button key={u.id} aria-current={u.id === unit?.id} onClick={() => go(u.id)} className={u.status === "planned" ? "planned" : ""}>
                  <span className="s">
                    {unitNumber(u.id)} · {u.status === "planned" ? "planned" : `${done}/${u.problems.length} solved`}
                  </span>
                  <span className="t">{u.title.split(/:\s/)[0]}</span>
                </button>
              );
            })}
          </div>
        ))}
      </nav>
      <div className="jt-grid" style={{ gap: "1.1rem" }}>
        {unit === null ? <Overview progress={progress} go={go} /> :
          <UnitPage key={unit.id} unit={unit} problemId={problemId} progress={progress}
            openProblem={(p) => { setProblemId(p); writeParams(unit.id, p); }} onSolved={solved}
            onAnswered={answered} go={go} />}
      </div>
    </div>
  );
}

function Overview({ progress, go }: { progress: Progress; go: (u: string) => void }) {
  return (
    <>
      <section className="jt-panel jt-pad">
        <div className="jt-toolbar">
          <div>
            <div className="jt-eyebrow">From your first expression to the compiler</div>
            <h3 style={{ marginTop: "0.25rem" }}>{course.units.length} units in four tracks</h3>
          </div>
          <ServerPill />
        </div>
        <p className="jt-muted" style={{ maxWidth: "50rem" }}>
          Every example's output on this site was produced by running it on Julia {course.julia}; none is typed by
          hand. Practice problems are graded by running your code in your own Julia against a hidden reference
          solution: first on correctness, then on speed, memory, growth and type stability relative to that reference.
        </p>
      </section>
      <div className="jt-tracks">
        {course.tracks.map((t) => {
          const units = course.units.filter((u) => u.track === t);
          return (
            <section key={t} className="jt-panel jt-pad">
              <div className="jt-eyebrow">{TRACK_LABEL[t]}</div>
              <p className="jt-small jt-muted" style={{ margin: "0.3rem 0 0.6rem" }}>{TRACK_BLURB[t]}</p>
              <ol className="jt-unitlist">
                {units.map((u) => {
                  const done = u.problems.filter((p) => progress.solved[p.id]).length;
                  return (
                    <li key={u.id}>
                      <button className="jt-linkbtn" onClick={() => go(u.id)}>
                        <span className="num">{unitNumber(u.id)}</span>
                        <span className="title">{u.title.split(/:\s/)[0]}</span>
                        <span className="meta">{u.status === "planned" ? "planned" :
                          u.problems.length ? `${done}/${u.problems.length}` : ""}</span>
                      </button>
                    </li>
                  );
                })}
              </ol>
            </section>
          );
        })}
      </div>
    </>
  );
}

function UnitPage({ unit, problemId, progress, openProblem, onSolved, onAnswered, go }: {
  unit: Unit;
  problemId: string | null;
  progress: Progress;
  openProblem: (p: string | null) => void;
  onSolved: (pid: string, r: GradeResult) => void;
  onAnswered: (key: string, firstTry: boolean) => void;
  go: (u: string) => void;
}) {
  const qkeys = unit.sections.flatMap((s, i) => s.questions.map((_, k) => `${unit.id}/${i}/${k}`));
  const qdone = qkeys.filter((k) => progress.questions[k]);
  const qfirst = qdone.filter((k) => progress.questions[k] === "first-try");
  const idx = course.units.indexOf(unit);
  const prev = course.units[idx - 1];
  const next = course.units[idx + 1];
  const [title, subtitle] = unit.title.split(/:\s/, 2);
  const problem = unit.problems.find((p) => p.id === problemId) ?? null;
  const practice = useRef<HTMLElement>(null);
  useEffect(() => { if (problemId) practice.current?.scrollIntoView({ block: "start" }); }, []); // eslint-disable-line

  return (
    <>
      <header className="jt-panel jt-pad">
        <div className="jt-eyebrow">{TRACK_LABEL[unit.track]} · unit {unitNumber(unit.id)}</div>
        <h2 style={{ margin: "0.3rem 0 0.2rem" }}>{title}</h2>
        {subtitle && <p className="jt-unit-sub">{subtitle}</p>}
        <p style={{ maxWidth: "48rem" }}>{md(unit.summary)}</p>
        <div className="jt-chips">
          {unit.kcs.map((k) => <span key={k} className="jt-chip kc">{k}</span>)}
          <span className="jt-chip info" title="Where this unit's code runs">
            env: {unit.env}{unit.env !== "base" && course.envs[unit.env] ? ` · ${course.envs[unit.env].map((p) => `${p.name} ${p.version}`).join(", ")}` : ""}
          </span>
          {unit.prerequisites.map((p) => (
            <button key={p} className="jt-chip jt-chipbtn" onClick={() => go(p)}>after {unitNumber(p)}</button>
          ))}
          {unit.lessons.map((l) => <a key={l} className="jt-chip" href="lessons.html">quiz: {l}</a>)}
          {qkeys.length > 0 && (
            <span className="jt-chip" title="Concept questions answered in this browser (right on the first pick)">
              concept questions: {qdone.length}/{qkeys.length}{qdone.length ? ` · ${qfirst.length} first try` : ""}
            </span>
          )}
        </div>
      </header>

      {unit.status === "planned" ? (
        <section className="jt-panel jt-pad">
          <div className="jt-eyebrow">Planned</div>
          <h3 style={{ marginTop: "0.25rem" }}>What this unit will cover</h3>
          <ul>{unit.outline.map((o, i) => <li key={i}>{md(o)}</li>)}</ul>
          <p className="jt-small jt-muted">
            Not written yet. Units are published only when every example has a recorded output and every problem's
            grader passes its own tests.
          </p>
        </section>
      ) : (
        unit.sections.map((s, i) => (
          <section key={i} className="jt-panel jt-pad jt-lesson-section">
            <div className="jt-eyebrow">{unitNumber(unit.id)}.{i + 1}</div>
            <h3 style={{ marginTop: "0.2rem" }}>{s.title}</h3>
            <Markdown text={s.body} />
            {s.examples.map((e, j) => <ExampleBlock key={j} ex={e} env={unit.env} id={`${unit.id}/${i}/${j}`} />)}
            {s.questions.map((q, k) => (
              <QuestionBlock key={k} q={q} number={k + 1} total={s.questions.length}
                onSettled={(firstTry) => onAnswered(`${unit.id}/${i}/${k}`, firstTry)} />
            ))}
          </section>
        ))
      )}

      {unit.problems.length > 0 && (
        <section className="jt-panel jt-pad" ref={practice} aria-labelledby="jt-practice">
          <div className="jt-toolbar">
            <div>
              <div className="jt-eyebrow">Practice</div>
              <h3 id="jt-practice" style={{ marginTop: "0.2rem" }}>Write it, run it, get graded</h3>
            </div>
            <ServerPill />
          </div>
          <div className="jt-problem-tabs" role="tablist">
            {unit.problems.map((p) => (
              <button key={p.id} role="tab" aria-selected={p.id === problem?.id} onClick={() => openProblem(p.id === problem?.id ? null : p.id)}>
                <span className={`dot ${progress.solved[p.id] ?? ""}`} aria-hidden="true" />
                <span className="t">{p.title}</span>
                <span className="s">{p.difficulty}{progress.solved[p.id] ? ` · solved (${progress.solved[p.id]})` : ""}</span>
              </button>
            ))}
          </div>
          {problem && <ProblemPanel key={problem.id} p={problem} onSolved={(r) => onSolved(problem.id, r)} />}
        </section>
      )}

      <div className="jt-row" style={{ justifyContent: "space-between" }}>
        {prev ? <button className="jt-btn" onClick={() => go(prev.id)}>← {unitNumber(prev.id)} {prev.title.split(/:\s/)[0]}</button> : <span />}
        {next && <button className="jt-btn" onClick={() => go(next.id)}>{unitNumber(next.id)} {next.title.split(/:\s/)[0]} →</button>}
      </div>
    </>
  );
}

function ExampleBlock({ ex, env, id }: { ex: Example; env: string; id: string }) {
  const [editing, setEditing] = useState(false);
  return (
    <figure className="jt-example">
      {ex.caption && <figcaption>{md(ex.caption)}</figcaption>}
      {editing ? (
        <RunBox initial={ex.code} env={env} storageKey={`example/${id}`} minRows={3} label="Edit the example" />
      ) : (
        <>
          <Code src={ex.code} />
          {ex.output !== null && (
            <pre className={`jt-output ${ex.ok ? "" : "err"}`} aria-label="Output">{ex.output || "(no output)"}</pre>
          )}
          {ex.images.map((src) => (
            <img key={src} className="jt-figure" src={src} loading="lazy"
              alt={`Figure produced by this example when it was recorded (${src.split("/").pop()})`} />
          ))}
          {ex.notice && ex.output !== null && <p className="jt-notice">{md(ex.notice)}</p>}
        </>
      )}
      <div className="jt-example-bar">
        {ex.mode === "file" && <span className="jt-chip info" title="Run with script (include) semantics, not the REPL's">as a file</span>}
        {!ex.check && <span className="jt-chip advice" title="This output varies between runs; it is recorded, not compared">varies per run</span>}
        <button className="jt-btn ghost jt-small" onClick={() => setEditing((x) => !x)}>
          {editing ? "Show the recorded output" : "Edit and run"}
        </button>
      </div>
    </figure>
  );
}

const LETTERS = "ABCDEF";

/**
 * A concept question: pick until right. Each wrong pick shows the
 * misconception it stands for; the explanation comes once the answer is found.
 */
function QuestionBlock({ q, number, total, onSettled }: {
  q: Question; number: number; total: number; onSettled: (firstTry: boolean) => void;
}) {
  const [picks, setPicks] = useState<number[]>([]);
  const st = questionState(q, picks);
  const pick = (i: number) => {
    if (st.done || picks.includes(i)) return;
    const next = [...picks, i];
    setPicks(next);
    const n = questionState(q, next);
    if (n.done) onSettled(n.firstTry);
  };
  const last = picks[picks.length - 1];
  return (
    <div className="jt-question" aria-live="polite">
      <div className="jt-eyebrow">
        {q.kind === "output" ? "Predict the output" : "Check your understanding"}{total > 1 ? ` · ${number} of ${total}` : ""}
      </div>
      <div className="jt-question-prompt"><Markdown text={q.prompt} /></div>
      {q.code && <Code src={q.code} />}
      <div className="jt-options" role="group" aria-label="Answer options">
        {q.choices.map((c, k) => {
          const i = k + 1;
          const cls = st.done && i === q.answer ? "right" : st.wrong.includes(i) ? "wrong" : "";
          return (
            <button key={i} className={`jt-option ${cls}`} disabled={st.done || picks.includes(i)} onClick={() => pick(i)}>
              <span className="letter">{LETTERS[k]}</span>
              {q.kind === "output" ? <code className="jt-option-code">{c}</code> : <span>{md(c)}</span>}
            </button>
          );
        })}
      </div>
      {!st.done && last !== undefined && (
        <div className="jt-callout mis"><span className="tag">Not quite</span><div>{md(q.misconceptions[last - 1])}</div></div>
      )}
      {st.done && (
        <div className={`jt-callout ${st.firstTry ? "ok" : "reveal"}`}>
          <span className="tag">{st.firstTry ? "Correct" : `Answer ${LETTERS[q.answer - 1]}`}</span>
          <div>{md(q.explain)}{q.kind === "output" && <div className="jt-small jt-muted" style={{ marginTop: "0.3rem" }}>
            The answer is the output recorded when this code ran on Julia {course.julia}.</div>}</div>
        </div>
      )}
    </div>
  );
}

function ProblemPanel({ p, onSolved }: { p: Problem; onSolved: (r: GradeResult) => void }) {
  const [code, setCode] = useDraft(`problem/${p.id}`, p.starter);
  const { status } = useServer();
  const [result, setResult] = useState<GradeResult | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [hints, setHints] = useState(0);
  const connected = status.kind === "connected";

  const grade = async () => {
    if (!connected || busy) return;
    setBusy(true); setError(null);
    try {
      const r = await gradeCode(p.id, code);
      setResult(r);
      if (r.status === "passed") onSolved(r);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  };

  const how = p.compare === "isapprox" ? `isapprox (rtol ${p.rtol})` : "isequal";
  return (
    <article className="jt-problem">
      <div className="jt-chips" style={{ marginBottom: "0.5rem" }}>
        <span className="jt-chip">{p.difficulty}</span>
        {p.kcs.map((k) => <span key={k} className="jt-chip kc">{k}</span>)}
        <span className="jt-chip info">define <code>{p.entry}</code></span>
      </div>
      <Markdown text={p.prompt} />
      {p.samples.length > 0 && (
        <table className="jt-samples">
          <caption className="jt-small jt-muted">The reference solution on the shown cases</caption>
          <tbody>
            {p.samples.map((s) => (
              <tr key={s.call}><td><code>{s.call}</code></td><td><code>{s.result}</code></td></tr>
            ))}
          </tbody>
        </table>
      )}
      <p className="jt-small jt-muted">
        Graded on these {p.samples.length} cases{p.random_cases ? " plus seeded random cases" : ""}, compared with {how}
        {p.check_type ? ", result types included" : ""}.
        {p.perf ? ` Then speed and memory against the reference at n = ${p.perf.sizes.join(" and ")}${p.perf.sizes.length === 2 ? " (growth from the two)" : ""}, and type stability.` : ""}
      </p>
      {!connected && <ConnectPanel compact />}
      <Editor value={code} onChange={setCode} onRun={grade} label={`Your solution for ${p.title}`} minRows={10} />
      <div className="jt-row">
        <button className="jt-btn primary" disabled={!connected || busy} onClick={grade}>
          {busy ? "Grading…" : "Submit"} <span className="jt-kbd">Ctrl ⏎</span>
        </button>
        {hints < p.hints.length && (
          <button className="jt-btn ghost jt-small" onClick={() => setHints((h) => h + 1)}>
            {hints === 0 ? "Show a hint" : "Another hint"} ({hints}/{p.hints.length})
          </button>
        )}
        {code !== p.starter && <button className="jt-btn ghost jt-small" onClick={() => setCode(p.starter)}>Back to the starter</button>}
      </div>
      {p.hints.slice(0, hints).map((h, i) => (
        <div key={i} className="jt-callout hint"><span className="tag">Hint {i + 1}</span><div>{md(h)}</div></div>
      ))}
      {busy && <Output result={null} error={null} running />}
      {error && <Output result={null} error={error} running={false} />}
      {result && !busy && <Feedback r={result} />}
    </article>
  );
}
