import { useEffect, useRef, useState } from "react";
import { Code } from "../components/Code";
import { Editor } from "../components/Editor";
import { Feedback } from "../components/Feedback";
import { Markdown, md } from "../components/Markdown";
import { ConnectPanel, Output, RunBox, ServerPill, useDraft } from "../components/Runner";
import {
  course, courseById, estimateText, landingHref, questionState, statusNote, TRACK_BLURB, TRACK_LABEL, trackRequirement, unitNumber,
  type Bug, type CourseInfo, type Example, type Explorer, type Problem, type Question, type Unit,
} from "../course";
import { bugRates, bugTestCode, bumpBug, hintsOpen, reading, unitBugs, type BugReading, type BugRecord } from "../findbug";
import { predictionKey, predictionRates, settlePrediction, unitPredictionKeys, type PredictionRecord } from "../predict";
import { choiceRates, costText, MAX_REASON, reasonOk, settleChoice, unitChoiceKeys, type ChoiceRecord } from "../choose";
import { breakRates, juliaNumber, parseValue, probeCode, readProbe, settleBreak, sweepWith, unitBreakKeys, type BreakRecord } from "../breakit";
import { drawable, extent, juliaValue, lines, localSlope, scale, startSelection, ticks, valueAt, type Selection } from "../explore";
import { assemble, bumpParsons, displayOrder, parsonsFeedback, parsonsRates, unitParsons, type ParsonsFeedback, type ParsonsRecord } from "../parsons";
import { loadProgress, saveProgress, type Progress } from "../progress";
import { gradeCode, runCode, useServer, type GradeResult, type RunResult } from "../server";

// A course's tracks, in track order (a track is listed once it has a unit).
const tracksOf = (c: CourseInfo) => course.tracks.filter((t) => course.units.some((u) => u.course === c.id && u.track === t));

function readParams() {
  const q = new URLSearchParams(window.location.search);
  return { unit: q.get("unit"), problem: q.get("problem"), course: q.get("course") };
}

// A unit names its course itself; ?course= matters only on a course's overview.
function writeParams(unit: string | null, problem: string | null, courseId: string | null) {
  const q = new URLSearchParams();
  if (unit) q.set("unit", unit);
  else if (courseId) q.set("course", courseId);
  if (problem) q.set("problem", problem);
  const s = q.toString();
  history.replaceState(null, "", window.location.pathname + (s ? `?${s}` : ""));
}

export function CourseView() {
  const [unitId, setUnitId] = useState<string | null>(() => readParams().unit);
  const [problemId, setProblemId] = useState<string | null>(() => readParams().problem);
  const [courseId, setCourseId] = useState<string>(() => readParams().course ?? course.courses[0].id);
  const [progress, setProgress] = useState<Progress>(loadProgress);
  const unit = course.units.find((u) => u.id === unitId) ?? null;
  // The syllabus shows one course: the open unit's, else the chosen one.
  const active = courseById(unit?.course ?? courseId) ?? course.courses[0];
  const units = course.units.filter((u) => u.course === active.id);
  const top = useRef<HTMLDivElement>(null);

  const pick = (c: string) => { setCourseId(c); setUnitId(null); setProblemId(null); writeParams(null, null, c); };
  const go = (u: string | null, p: string | null = null) => {
    // following a unit into another course (a prerequisite) switches the syllabus to it
    const uc = u ? course.units.find((x) => x.id === u)?.course : undefined;
    if (uc) setCourseId(uc);
    setUnitId(u); setProblemId(p); writeParams(u, p, uc ?? active.id);
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
  // A prediction is committed once: the first record is kept, never replaced.
  const predicted = (key: string, r: PredictionRecord) =>
    setProgress((s) => s.predictions[key] ? s : saveProgress({ ...s, predictions: { ...s.predictions, [key]: r } }));
  // A method choice too: the first record (pick, reason, verdict) is kept.
  const chose = (key: string, r: ChoiceRecord) =>
    setProgress((s) => s.choices[key] ? s : saveProgress({ ...s, choices: { ...s.choices, [key]: r } }));
  // A break-it edge too: the first committed value is kept.
  const broke = (key: string, r: BreakRecord) =>
    setProgress((s) => s.breaks[key] ? s : saveProgress({ ...s, breaks: { ...s.breaks, [key]: r } }));
  // A find-the-bug record counts test runs and hints until it is fixed, then freezes.
  const bugged = (pid: string, what: "run" | "hint" | "fixed") =>
    setProgress((s) => saveProgress({ ...s, bugs: { ...s.bugs, [pid]: bumpBug(s.bugs[pid], what) } }));
  // A Parsons record counts checks until the order works, then freezes.
  const parsoned = (pid: string, solvedNow: boolean) =>
    setProgress((s) => saveProgress({ ...s, parsons: { ...s.parsons, [pid]: bumpParsons(s.parsons[pid], solvedNow) } }));

  return (
    <div className="jt-split jt-course" ref={top}>
      <nav className="jt-panel jt-nav jt-syllabus" aria-label="Syllabus">
        <div className="jt-coursetabs" role="group" aria-label="Course">
          {course.courses.map((c) => (
            <button key={c.id} className={`jt-chip jt-chipbtn${c.id === active.id ? " kc" : ""}`} aria-pressed={c.id === active.id}
              onClick={() => pick(c.id)}>
              {c.title}{statusNote(c) ? ` · ${statusNote(c)}` : ""}
            </button>
          ))}
        </div>
        <button aria-current={unit === null} onClick={() => go(null)}>
          <span className="s">{units.filter((u) => u.status === "ready").length} units ready · {active.problems} problems{statusNote(active) ? ` · ${statusNote(active)}` : ""}</span>
          <span className="t">{active.title}: overview</span>
        </button>
        {tracksOf(active).map((t) => (
          <div key={t}>
            <div className="jt-eyebrow" style={{ padding: "0.7rem 0.7rem 0.2rem" }}>{TRACK_LABEL[t]}</div>
            {units.filter((u) => u.track === t).map((u) => {
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
        {unit === null ? <Overview c={active} progress={progress} go={go} /> :
          <UnitPage key={unit.id} unit={unit} problemId={problemId} progress={progress}
            openProblem={(p) => { setProblemId(p); writeParams(unit.id, p, active.id); }} onSolved={solved}
            onAnswered={answered} onPredicted={predicted} onChose={chose} onBroke={broke} onBug={bugged}
            onParsons={parsoned} go={go} />}
      </div>
    </div>
  );
}

function Overview({ c, progress, go }: { c: CourseInfo; progress: Progress; go: (u: string) => void }) {
  const tracks = tracksOf(c);
  const note = statusNote(c);
  return (
    <>
      <section className="jt-panel jt-pad">
        <div className="jt-toolbar">
          <div>
            <div className="jt-eyebrow">Course {c.order} of {course.courses.length}{note && <> · <span className="jt-chip advice">{note}</span></>}</div>
            <h3 style={{ marginTop: "0.25rem" }}>{c.title}: {c.units.length} units in {tracks.length} {tracks.length === 1 ? "track" : "tracks"}</h3>
          </div>
          <ServerPill />
        </div>
        <p style={{ maxWidth: "50rem" }}>{c.summary}</p>
        {note && <p className="jt-small" style={{ maxWidth: "50rem" }}><strong>Not finished.</strong> {c.status_note}</p>}
        <p className="jt-small" style={{ maxWidth: "50rem" }}>
          <a href={landingHref(c.id)}>Outcomes, prerequisites and setup</a> · {estimateText(c)}
        </p>
        <p className="jt-muted" style={{ maxWidth: "50rem" }}>
          Every example's output on this site was produced by running it on Julia {course.julia}; none is typed by
          hand. Practice problems are graded by running your code in your own Julia against a hidden reference
          solution: first on correctness, then on speed, memory, growth and type stability relative to that reference.
        </p>
      </section>
      <PredictionRates c={c} progress={progress} />
      <ChoiceRates c={c} progress={progress} />
      <BreakRates c={c} progress={progress} />
      <BugRates c={c} progress={progress} />
      <ParsonsRates c={c} progress={progress} />
      <div className="jt-tracks">
        {tracks.map((t) => {
          const units = course.units.filter((u) => u.course === c.id && u.track === t);
          return (
            <section key={t} className="jt-panel jt-pad">
              <div className="jt-eyebrow">{TRACK_LABEL[t]}</div>
              <p className="jt-small jt-muted" style={{ margin: "0.3rem 0 0.6rem" }}>{TRACK_BLURB[t]}</p>
              {trackRequirement(t) && <p className="jt-small" style={{ margin: "0 0 0.6rem" }}>{trackRequirement(t)}</p>}
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

function UnitPage({ unit, problemId, progress, openProblem, onSolved, onAnswered, onPredicted, onChose, onBroke, onBug, onParsons, go }: {
  unit: Unit;
  problemId: string | null;
  progress: Progress;
  openProblem: (p: string | null) => void;
  onSolved: (pid: string, r: GradeResult) => void;
  onAnswered: (key: string, firstTry: boolean) => void;
  onPredicted: (key: string, r: PredictionRecord) => void;
  onChose: (key: string, r: ChoiceRecord) => void;
  onBroke: (key: string, r: BreakRecord) => void;
  onBug: (pid: string, what: "run" | "hint" | "fixed") => void;
  onParsons: (pid: string, solved: boolean) => void;
  go: (u: string) => void;
}) {
  const bugs = unitBugs(unit);
  const parsons = unitParsons(unit);
  const parsonsSolved = parsons.filter((p) => progress.parsons[p.id]?.solved);
  const bugsFixed = bugs.filter((p) => progress.bugs[p.id]?.fixed);
  const pkeys = unitPredictionKeys(unit);
  const pmade = pkeys.filter((k) => progress.predictions[k]?.pick);
  const phits = pmade.filter((k) => progress.predictions[k].hit);
  const ckeys = unitChoiceKeys(unit);
  const cmade = ckeys.filter((k) => progress.choices[k]?.pick);
  const cgood = cmade.filter((k) => progress.choices[k].verdict === "good");
  const bkeys = unitBreakKeys(unit);
  const bmade = bkeys.filter((k) => progress.breaks[k] && progress.breaks[k].value !== null);
  const bfound = bmade.filter((k) => progress.breaks[k].verdict === "found");
  const qkeys = unit.sections.flatMap((s, i) => s.questions.map((_, k) => `${unit.id}/${i}/${k}`));
  const qdone = qkeys.filter((k) => progress.questions[k]);
  const qfirst = qdone.filter((k) => progress.questions[k] === "first-try");
  const own = courseById(unit.course);
  const siblings = course.units.filter((u) => u.course === unit.course);
  const idx = siblings.indexOf(unit);
  const prev = siblings[idx - 1];
  const next = siblings[idx + 1];
  const [title, subtitle] = unit.title.split(/:\s/, 2);
  const problem = unit.problems.find((p) => p.id === problemId) ?? null;
  const practice = useRef<HTMLElement>(null);
  useEffect(() => { if (problemId) practice.current?.scrollIntoView({ block: "start" }); }, []); // eslint-disable-line

  return (
    <>
      <header className="jt-panel jt-pad">
        <div className="jt-eyebrow">
          {own ? <a href={landingHref(own.id)}>{own.title}</a> : null}
          {TRACK_LABEL[unit.track] !== own?.title && <> · {TRACK_LABEL[unit.track]}</>} · unit {unitNumber(unit.id)}
          {own && statusNote(own) && <> · <span className="jt-chip advice" title="This course is not finished">course {statusNote(own)}</span></>}
        </div>
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
          {pkeys.length > 0 && (
            <span className="jt-chip" title="Predictions committed in this browser before seeing the output, and how many were right">
              predictions: {pmade.length}/{pkeys.length}{pmade.length ? ` · ${phits.length} right` : ""}
            </span>
          )}
          {ckeys.length > 0 && (
            <span className="jt-chip" title="Method choices committed in this browser before seeing the measurements, and how many were good">
              method choices: {cmade.length}/{ckeys.length}{cmade.length ? ` · ${cgood.length} good` : ""}
            </span>
          )}
          {bkeys.length > 0 && (
            <span className="jt-chip" title="Break-it edges committed in this browser before seeing the sweep, and how many were inside the measured edge">
              break it: {bmade.length}/{bkeys.length}{bmade.length ? ` · ${bfound.length} found` : ""}
            </span>
          )}
          {bugs.length > 0 && (
            <span className="jt-chip" title="Find-the-bug problems fixed in this browser: the grader and every convergence test passed on the same code">
              find the bug: {bugsFixed.length}/{bugs.length} fixed
            </span>
          )}
          {parsons.length > 0 && (
            <span className="jt-chip" title="Parsons problems put in a working order in this browser">
              Parsons: {parsonsSolved.length}/{parsons.length} in order
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
            {s.examples.map((e, j) => {
              const key = predictionKey(unit.id, i, j);
              return <ExampleBlock key={j} ex={e} env={unit.env} id={key}
                record={progress.predictions[key] ?? null} onPredicted={(r) => onPredicted(key, r)}
                choice={progress.choices[key] ?? null} onChose={(r) => onChose(key, r)}
                broke={progress.breaks[key] ?? null} onBroke={(r) => onBroke(key, r)} />;
            })}
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
          {problem && (problem.parsons ?
            <ParsonsProblem key={problem.id} p={problem} onSolved={(r) => onSolved(problem.id, r)}
              record={progress.parsons[problem.id] ?? null} onCheck={(ok) => onParsons(problem.id, ok)} /> :
            <ProblemPanel key={problem.id} p={problem} env={unit.env} onSolved={(r) => onSolved(problem.id, r)}
              bugRecord={progress.bugs[problem.id] ?? null} onBug={(what) => onBug(problem.id, what)} />)}
        </section>
      )}

      <div className="jt-row" style={{ justifyContent: "space-between" }}>
        {prev ? <button className="jt-btn" onClick={() => go(prev.id)}>← {unitNumber(prev.id)} {prev.title.split(/:\s/)[0]}</button> : <span />}
        {next && <button className="jt-btn" onClick={() => go(next.id)}>{unitNumber(next.id)} {next.title.split(/:\s/)[0]} →</button>}
      </div>
    </>
  );
}

/**
 * Hits per knowledge component over this course's predictions, from this
 * browser's records. Nothing is sent anywhere.
 */
function PredictionRates({ c, progress }: { c: CourseInfo; progress: Progress }) {
  const units = course.units.filter((u) => u.course === c.id);
  const total = units.reduce((n, u) => n + unitPredictionKeys(u).length, 0);
  if (total === 0) return null;
  const rates = predictionRates(progress.predictions, units);
  return (
    <section className="jt-panel jt-pad" aria-labelledby="jt-pred-rates">
      <div className="jt-eyebrow">Predict, then run</div>
      <h3 id="jt-pred-rates" style={{ marginTop: "0.25rem" }}>Your predictions, by knowledge component</h3>
      <p className="jt-small" style={{ maxWidth: "50rem" }}>
        {total} examples in this course ask for a prediction before their output is shown. Each answer was read from
        the recorded output, not written by hand. Only your first pick counts, and the record stays in this browser.
      </p>
      {rates.length === 0 ? <p className="jt-small jt-muted">No predictions committed yet.</p> : (
        <table className="jt-table jt-small">
          <thead><tr><th scope="col">Knowledge component</th><th scope="col">Right before seeing the output</th></tr></thead>
          <tbody>
            {rates.map((r) => <tr key={r.kc}><td><code>{r.kc}</code></td><td>{r.hits} of {r.total}</td></tr>)}
          </tbody>
        </table>
      )}
    </section>
  );
}

/**
 * Good method choices per knowledge component over this course's checkpoints,
 * from this browser's records. Nothing is sent anywhere.
 */
function ChoiceRates({ c, progress }: { c: CourseInfo; progress: Progress }) {
  const units = course.units.filter((u) => u.course === c.id);
  const total = units.reduce((n, u) => n + unitChoiceKeys(u).length, 0);
  if (total === 0) return null;
  const rates = choiceRates(progress.choices, units);
  return (
    <section className="jt-panel jt-pad" aria-labelledby="jt-choice-rates">
      <div className="jt-eyebrow">Method-choice checkpoints</div>
      <h3 id="jt-choice-rates" style={{ marginTop: "0.25rem" }}>Your method choices, by knowledge component</h3>
      <p className="jt-small" style={{ maxWidth: "50rem" }}>
        {total} examples in this course ask you to pick a method and give a reason before their measurements are shown.
        A choice is scored against the recorded counts: good if it is within the stated factor of the cheapest method
        that meets the accuracy. Your reasons are not graded; they stay in this browser, next to the numbers.
      </p>
      {rates.length === 0 ? <p className="jt-small jt-muted">No method chosen yet.</p> : (
        <table className="jt-table jt-small">
          <thead><tr><th scope="col">Knowledge component</th><th scope="col">Good choices</th></tr></thead>
          <tbody>
            {rates.map((r) => <tr key={r.kc}><td><code>{r.kc}</code></td><td>{r.good} of {r.total}</td></tr>)}
          </tbody>
        </table>
      )}
    </section>
  );
}

const VERDICT_TEXT = { good: "good", costly: "costly", fails: "misses the accuracy" } as const;

/** The gate before a checkpoint's output: pick one method, write one line, commit. */
function ChoiceGate({ ex, onChose }: { ex: Example; onChose: (r: ChoiceRecord) => void }) {
  const c = ex.choose!;
  const [pick, setPick] = useState(0);
  const [reason, setReason] = useState("");
  const ready = pick > 0 && reasonOk(reason);
  return (
    <figure className="jt-example">
      {ex.caption && <figcaption>{md(ex.caption)}</figcaption>}
      <Code src={ex.code} />
      <div className="jt-question">
        <div className="jt-eyebrow">Method choice · one pick and a reason, scored once</div>
        <div className="jt-question-prompt"><Markdown text={c.prompt} /></div>
        <div className="jt-options" role="radiogroup" aria-label="Methods">
          {c.choices.map((t, k) => (
            <button key={k} role="radio" aria-checked={pick === k + 1}
              className={`jt-option${pick === k + 1 ? " picked" : ""}`} onClick={() => setPick(k + 1)}>
              <span className="letter">{LETTERS[k]}</span><span>{md(t)}</span>
            </button>
          ))}
        </div>
        <label className="jt-small" style={{ display: "block" }}>
          Why this one? One line, in your own words (not graded; kept in this browser)
          <input className="jt-input" style={{ display: "block", width: "100%", marginTop: "0.3rem" }}
            maxLength={MAX_REASON} value={reason} onChange={(e) => setReason(e.target.value)}
            onKeyDown={(e) => { if (e.key === "Enter" && ready) onChose(settleChoice(c, pick, reason)); }} />
        </label>
        <div className="jt-row" style={{ marginTop: "0.6rem" }}>
          <button className="jt-btn" disabled={!ready} onClick={() => onChose(settleChoice(c, pick, reason))}>
            Commit and show the measurements
          </button>
          {!ready && <span className="jt-small jt-muted">{pick === 0 ? "Pick a method." : "Write a reason."}</span>}
        </div>
      </div>
      <div className="jt-example-bar">
        <button className="jt-btn ghost jt-small" onClick={() => onChose(settleChoice(c, 0, ""))}>
          Show the measurements without choosing
        </button>
      </div>
    </figure>
  );
}

/** After the commit: the verdict, the learner's reason, and the measured table it was scored against. */
function ChoiceResult({ ex, r }: { ex: Example; r: ChoiceRecord }) {
  const c = ex.choose!;
  const tone = r.verdict === "skipped" ? "reveal" : r.verdict === "good" ? "ok" : "mis";
  const tag = { skipped: "Not chosen", good: "Good choice", costly: "Works, but costly", fails: "Misses the accuracy" }[r.verdict];
  return (
    <div className={`jt-callout ${tone}`}>
      <span className="tag">{tag}</span>
      <div>
        {r.pick > 0 && (
          <div className="jt-small">
            You picked {LETTERS[r.pick - 1]}{r.reason ? <>, because: “{r.reason}”</> : null}. Compare your reason with the
            counts below.
          </div>
        )}
        <table className="jt-table jt-small" style={{ margin: "0.4rem 0" }}>
          <caption className="jt-muted" style={{ textAlign: "left", captionSide: "top" }}>
            Measured in the output above: {c.cost}. Good: within {c.band}× of the cheapest method that meets the accuracy.
          </caption>
          <thead><tr><th scope="col">Method</th><th scope="col">Cost</th><th scope="col">Verdict</th></tr></thead>
          <tbody>
            {c.choices.map((t, k) => (
              <tr key={k} aria-current={r.pick === k + 1 ? "true" : undefined}>
                <td>{LETTERS[k]} · {md(t.split(/:\s/)[0])}{r.pick === k + 1 ? " (yours)" : ""}</td>
                <td>{costText(c, k)}</td>
                <td>{VERDICT_TEXT[c.verdicts[k]]}</td>
              </tr>
            ))}
          </tbody>
        </table>
        {r.pick > 0 && c.misconceptions[r.pick - 1] && <div>{md(c.misconceptions[r.pick - 1])}</div>}
        <div style={{ marginTop: "0.3rem" }}>{md(c.explain)}</div>
      </div>
    </div>
  );
}

/**
 * Edges found per knowledge component over this course's break-it
 * challenges, from this browser's records. Nothing is sent anywhere.
 */
function BreakRates({ c, progress }: { c: CourseInfo; progress: Progress }) {
  const units = course.units.filter((u) => u.course === c.id);
  const total = units.reduce((n, u) => n + unitBreakKeys(u).length, 0);
  if (total === 0) return null;
  const rates = breakRates(progress.breaks, units);
  return (
    <section className="jt-panel jt-pad" aria-labelledby="jt-break-rates">
      <div className="jt-eyebrow">Break it</div>
      <h3 id="jt-break-rates" style={{ marginTop: "0.25rem" }}>Your break-it edges, by knowledge component</h3>
      <p className="jt-small" style={{ maxWidth: "50rem" }}>
        {total} examples in this course ask where a method stops working before their sweep is shown. An edge counts
        as found when it lies between the two swept values where the recorded measurement changes from working to
        failing. Only your first value counts, and the record stays in this browser.
      </p>
      {rates.length === 0 ? <p className="jt-small jt-muted">No edge committed yet.</p> : (
        <table className="jt-table jt-small">
          <thead><tr><th scope="col">Knowledge component</th><th scope="col">Edges found</th></tr></thead>
          <tbody>
            {rates.map((r) => <tr key={r.kc}><td><code>{r.kc}</code></td><td>{r.found} of {r.total}</td></tr>)}
          </tbody>
        </table>
      )}
    </section>
  );
}

/**
 * The gate before a break-it sweep: optionally run the probe at values of the
 * learner's choice (needs `tutor serve`), then commit one value as the edge.
 */
function BreakGate({ ex, env, onBroke }: { ex: Example; env: string; onBroke: (r: BreakRecord) => void }) {
  const b = ex.breakit!;
  const { status } = useServer();
  const connected = status.kind === "connected" && status.envs.includes(env);
  const [edge, setEdge] = useState("");
  const [trial, setTrial] = useState("");
  const [runs, setRuns] = useState<{ v: number; result: RunResult | null; error: string | null }[]>([]);
  const [running, setRunning] = useState(false);
  const value = parseValue(edge);
  const tv = parseValue(trial);
  const commit = () => { if (value !== null) onBroke(settleBreak(b, value, runs.length)); };
  const probe = async () => {
    if (tv === null || running || !connected) return;
    setRunning(true);
    try {
      const result = await runCode(probeCode(b, tv), env);
      setRuns((rs) => [{ v: tv, result, error: null }, ...rs]);
    } catch (e) {
      setRuns((rs) => [{ v: tv, result: null, error: (e as Error).message }, ...rs]);
    } finally {
      setRunning(false);
    }
  };
  return (
    <figure className="jt-example">
      {ex.caption && <figcaption>{md(ex.caption)}</figcaption>}
      <Code src={ex.code} />
      <div className="jt-question">
        <div className="jt-eyebrow">Break it · one value, scored once</div>
        <div className="jt-question-prompt"><Markdown text={b.prompt} /></div>
        <div className="jt-small" style={{ margin: "0.4rem 0" }}>
          <strong>Probe</strong> (optional): run the computation at one value of <code>{b.param}</code> in your own Julia
          and read <em>{b.measure}</em>. It fails when that is {b.fails} {b.limit}, or NaN.
        </div>
        {connected ? (
          <div className="jt-row">
            <label className="jt-small">
              <code>{b.param}</code> ={" "}
              <input className="jt-input" style={{ width: "8rem" }} inputMode="decimal" value={trial} aria-label={`Value of ${b.param} to probe`}
                onChange={(e) => setTrial(e.target.value)} onKeyDown={(e) => { if (e.key === "Enter") probe(); }} />
            </label>
            <button className="jt-btn" disabled={tv === null || running} onClick={probe}>{running ? "Running…" : "Run the probe"}</button>
            {trial && tv === null && <span className="jt-small jt-muted">A positive number, such as 0.25 or 2.5e-1.</span>}
          </div>
        ) : (
          <p className="jt-small jt-muted">
            Connect <code>tutor serve</code> (with the <code>{env}</code> environment) to run the probe; without it, work the
            edge out and commit. <ServerPill />
          </p>
        )}
        {runs.length > 0 && (
          <table className="jt-table jt-small" style={{ margin: "0.4rem 0" }}>
            <caption className="jt-muted" style={{ textAlign: "left", captionSide: "top" }}>Your probe runs, newest first</caption>
            <thead><tr><th scope="col"><code>{b.param}</code></th><th scope="col">{b.measure}</th><th scope="col">The method</th></tr></thead>
            <tbody>
              {runs.map((r, k) => {
                const seen = r.result ? readProbe(b, r.result.output) : null;
                return (
                  <tr key={runs.length - k}>
                    <td>{juliaNumber(r.v)}</td>
                    <td>{seen ? seen.m : r.error ?? "(no row in the output)"}</td>
                    <td>{seen ? (seen.failed ? "fails" : "works") : r.result && !r.result.ok ? "the run ended with an error" : "?"}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        )}
        <label className="jt-small" style={{ display: "block", marginTop: "0.5rem" }}>
          Your edge: the value of <code>{b.param}</code> where the method stops working
          <input className="jt-input" style={{ display: "block", width: "12rem", marginTop: "0.3rem" }} inputMode="decimal"
            value={edge} onChange={(e) => setEdge(e.target.value)} onKeyDown={(e) => { if (e.key === "Enter") commit(); }} />
        </label>
        <div className="jt-row" style={{ marginTop: "0.6rem" }}>
          <button className="jt-btn" disabled={value === null} onClick={commit}>Commit and show the sweep</button>
          {value === null && <span className="jt-small jt-muted">{edge ? "A positive number, such as 0.25 or 2.5e-1." : "Type a value."}</span>}
        </div>
      </div>
      <div className="jt-example-bar">
        <button className="jt-btn ghost jt-small" onClick={() => onBroke(settleBreak(b, null, runs.length))}>
          Show the sweep without committing
        </button>
      </div>
    </figure>
  );
}

/** After the commit: the verdict and the recorded sweep, with the learner's value placed in it. */
function BreakResult({ ex, r }: { ex: Example; r: BreakRecord }) {
  const b = ex.breakit!;
  const tone = r.verdict === "skipped" ? "reveal" : r.verdict === "found" ? "ok" : "mis";
  const tag = { skipped: "Not committed", found: "Edge found", close: "Close to the edge",
                short: "The method still works there", past: "Well past the edge" }[r.verdict];
  const [lo, hi] = b.edge;
  return (
    <div className={`jt-callout ${tone}`}>
      <span className="tag">{tag}</span>
      <div>
        <div className="jt-small">
          {r.value !== null && <>You committed <code>{b.param} = {juliaNumber(r.value)}</code>
            {r.probes > 0 ? ` after ${r.probes} probe run${r.probes === 1 ? "" : "s"}` : ""}. </>}
          Measured in the output above: the method works at <code>{b.param} = {juliaNumber(b.side === "high" ? lo : hi)}</code> and
          fails at <code>{juliaNumber(b.side === "high" ? hi : lo)}</code>, so the edge lies between {juliaNumber(lo)} and {juliaNumber(hi)}.
        </div>
        <table className="jt-table jt-small" style={{ margin: "0.4rem 0" }}>
          <thead><tr><th scope="col"><code>{b.param}</code></th><th scope="col">{b.measure}</th><th scope="col">The method</th></tr></thead>
          <tbody>
            {sweepWith(b, r.value).map((row, k) => row.mine ? (
              <tr key={k} aria-current="true"><td>{juliaNumber(row.p)} (yours)</td><td colSpan={2}>your edge</td></tr>
            ) : (
              <tr key={k}><td>{juliaNumber(row.p)}</td><td>{row.m}</td><td>{row.failed ? "fails" : "works"}</td></tr>
            ))}
          </tbody>
        </table>
        {r.verdict === "short" && <div>{md(b.short)}</div>}
        {r.verdict === "past" && <div>{md(b.past)}</div>}
        <div style={{ marginTop: "0.3rem" }}>{md(b.explain)}</div>
      </div>
    </div>
  );
}

// One meaning per colour (CLAUDE.md): series are told apart by ink tone and dash, not by green or red.
const SERIES_STYLE = [
  { stroke: "var(--jt-ink)", dash: "" },
  { stroke: "var(--jt-blue)", dash: "6 4" },
  { stroke: "var(--jt-muted)", dash: "2 3" },
];

/**
 * A precomputed explorer: a slider per numeric axis (buttons for an axis of
 * words), the measure at the chosen point as the output printed it, and a
 * plot of the measure against the x axis. Every value is looked up in the
 * recorded grid; nothing is computed except the plot's geometry and, on
 * log-log axes, the slope between neighbouring printed values.
 */
function ExplorerPanel({ x }: { x: Explorer }) {
  const [sel, setSel] = useState<Selection>(() => startSelection(x));
  const set = (k: number, v: number) => setSel((s) => s.map((old, i) => (i === k ? v : old)));
  const xi = x.axes.findIndex((a) => a.group === x.x);
  const ax = x.axes[xi];
  const ls = lines(x, sel);
  const ext = extent(x.values.map(juliaValue), x.log);
  const slope = localSlope(x, sel);
  const W = 520, H = 260, L = 64, R = 14, T = 12, B = 38;
  const sx = scale(ax.nums[0], ax.nums[ax.nums.length - 1], L, W - R, ax.log);
  const sy = ext ? scale(ext[0], ext[1], H - B, T, x.log) : null;
  const fmt = (v: number) => (x.log || ax.log) && (v >= 1e4 || v < 1e-3) ? v.toExponential(0).replace("e+", "e") : String(v);
  const point = x.axes.map((a, k) => `${a.label}: ${a.texts[sel[k]]}`).join(" · ");
  const hidden = ls.flatMap((l) => l.points).filter((p) => !drawable(p.v, x.log)).length;
  return (
    <div className="jt-explore">
      <div className="jt-eyebrow">Explorer · precomputed by the reference; run it yourself with tutor serve</div>
      <div className="jt-question-prompt">{md(x.prompt)}</div>
      <div className="jt-explore-controls">
        {x.axes.map((a, k) => a.numeric ? (
          <label key={a.group} className="jt-explore-slider">
            <span>{a.label}: <code>{a.texts[sel[k]]}</code></span>
            <input type="range" min={0} max={a.texts.length - 1} step={1} value={sel[k]}
              aria-valuetext={a.texts[sel[k]]} onChange={(e) => set(k, Number(e.target.value))} />
          </label>
        ) : (
          <div key={a.group} className="jt-explore-choice" role="group" aria-label={a.label}>
            <span>{a.label}:</span>
            {a.texts.map((t, j) => (
              <button key={t} className={`jt-btn jt-small ${sel[k] === j ? "" : "ghost"}`} aria-pressed={sel[k] === j}
                onClick={() => set(k, j)}>{t}</button>
            ))}
          </div>
        ))}
      </div>
      <div className="jt-explore-readout" aria-live="polite">
        <span className="jt-muted">{point}</span><br />
        <strong>{x.label}: <code>{valueAt(x, sel)}</code></strong>
        {slope && <><br />Slope on log-log axes from <code>{x.x} = {slope.from}</code> to <code>{slope.to}</code>: <code>{slope.slope.toFixed(2)}</code> (from the printed values)</>}
      </div>
      {sy && x.series && (
        // A legend, not labels at the lines' ends: lines that end close together would overprint them.
        <div className="jt-explore-legend" aria-hidden="true">
          {ls.map((l, k) => {
            const st = SERIES_STYLE[k % SERIES_STYLE.length];
            return (
              <span key={l.label} className={l.current ? "current" : ""}>
                <svg width="28" height="10"><line x1="1" x2="27" y1="5" y2="5" stroke={st.stroke} strokeDasharray={st.dash} strokeWidth="2" /></svg>
                {l.label}
              </span>
            );
          })}
        </div>
      )}
      {sy && (
        <svg className="jt-explore-plot" viewBox={`0 0 ${W} ${H}`} role="img"
          aria-label={`${x.label} against ${ax.label}${x.series ? `, one line per ${x.axes.find((a) => a.group === x.series)!.label}` : ""}; the selected point is circled. The same values are in the table below.`}>
          {ticks(ext![0], ext![1], x.log, x.values.map(juliaValue).filter((v) => drawable(v, x.log))).map((t) => (
            <g key={`y${t}`}>
              <line x1={L} x2={W - R} y1={sy(t)} y2={sy(t)} className="grid" />
              <text x={L - 6} y={sy(t) + 4} textAnchor="end">{fmt(t)}</text>
            </g>
          ))}
          {ticks(ax.nums[0], ax.nums[ax.nums.length - 1], ax.log, ax.nums).map((t) => (
            <text key={`x${t}`} x={sx(t)} y={H - B + 16} textAnchor="middle">{fmt(t)}</text>
          ))}
          <text x={(L + W - R) / 2} y={H - 4} textAnchor="middle" className="axis">{ax.label}{ax.log ? " (log)" : ""}</text>
          {ls.map((l, k) => {
            const pts = l.points.filter((p) => drawable(p.v, x.log));
            const st = SERIES_STYLE[k % SERIES_STYLE.length];
            return (
              <g key={l.label} opacity={l.current ? 1 : 0.45}>
                <polyline fill="none" stroke={st.stroke} strokeDasharray={st.dash} strokeWidth={l.current ? 2.2 : 1.4}
                  points={pts.map((p) => `${sx(p.x)},${sy(p.v)}`).join(" ")} />
              </g>
            );
          })}
          {(() => {
            const cur = ls.find((l) => l.current)!.points[sel[xi]];
            return drawable(cur.v, x.log) ? <circle cx={sx(cur.x)} cy={sy(cur.v)} r={5} className="sel" /> : null;
          })()}
        </svg>
      )}
      {hidden > 0 && <p className="jt-small">{hidden} value{hidden === 1 ? "" : "s"} cannot be drawn on this scale (zero, negative, Inf or NaN); the table has them.</p>}
      <details>
        <summary className="jt-small">This slice as a table</summary>
        <table className="jt-table jt-small">
          <thead><tr><th scope="col"><code>{x.x}</code></th>{ls.map((l) => <th key={l.label} scope="col">{x.series ? l.label : x.label}</th>)}</tr></thead>
          <tbody>
            {ax.texts.map((t, j) => (
              <tr key={t} aria-current={j === sel[xi] ? "true" : undefined}>
                <td>{t}</td>{ls.map((l) => <td key={l.label}>{l.points[j].text}</td>)}
              </tr>
            ))}
          </tbody>
        </table>
      </details>
      <div style={{ marginTop: "0.4rem" }}>{md(x.explain)}</div>
    </div>
  );
}

function ExampleBlock({ ex, env, id, record, onPredicted, choice, onChose, broke, onBroke }: {
  ex: Example; env: string; id: string; record: PredictionRecord | null; onPredicted: (r: PredictionRecord) => void;
  choice: ChoiceRecord | null; onChose: (r: ChoiceRecord) => void;
  broke: BreakRecord | null; onBroke: (r: BreakRecord) => void;
}) {
  const [editing, setEditing] = useState(false);
  const p = ex.predict;
  // The sweep (output and notice) stays hidden until an edge is committed.
  if (ex.breakit && !broke) return <BreakGate ex={ex} env={env} onBroke={onBroke} />;
  // Like a prediction: the output, figures and notice stay hidden until a method is committed.
  if (ex.choose && !choice) return <ChoiceGate ex={ex} onChose={onChose} />;
  // The output (and the figures and notice, which describe it) stay hidden until a pick is committed.
  if (p && !record) {
    return (
      <figure className="jt-example">
        {ex.caption && <figcaption>{md(ex.caption)}</figcaption>}
        <Code src={ex.code} />
        <div className="jt-question" aria-live="polite">
          <div className="jt-eyebrow">Predict, then run · one pick, scored once</div>
          <div className="jt-question-prompt"><Markdown text={p.prompt} /></div>
          <div className="jt-options" role="group" aria-label="Prediction options">
            {p.choices.map((c, k) => (
              <button key={k} className="jt-option" onClick={() => onPredicted(settlePrediction(p, k + 1))}>
                <span className="letter">{LETTERS[k]}</span><span>{md(c)}</span>
              </button>
            ))}
          </div>
        </div>
        <div className="jt-example-bar">
          <button className="jt-btn ghost jt-small" onClick={() => onPredicted(settlePrediction(p, 0))}>
            Show the output without predicting
          </button>
        </div>
      </figure>
    );
  }
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
          {p && record && (
            <div className={`jt-callout ${record.pick === 0 ? "reveal" : record.hit ? "ok" : "mis"}`}>
              <span className="tag">{record.pick === 0 ? "Not predicted" : record.hit ? "Your prediction held" : "Not this time"}</span>
              <div>
                <div className="jt-small">
                  {record.pick > 0 && <>You picked {LETTERS[record.pick - 1]}. </>}
                  Measured in the output above: <code>{p.measured}</code>, so the answer is {LETTERS[p.answer - 1]} ({md(p.choices[p.answer - 1])}).
                </div>
                <div style={{ marginTop: "0.3rem" }}>{md(p.explain)}</div>
              </div>
            </div>
          )}
          {ex.choose && choice && <ChoiceResult ex={ex} r={choice} />}
          {ex.breakit && broke && <BreakResult ex={ex} r={broke} />}
          {ex.explore && ex.output !== null && <ExplorerPanel x={ex.explore} />}
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

/** Find-the-bug problems fixed per knowledge component, over the ones worked on in this browser. */
function BugRates({ c, progress }: { c: CourseInfo; progress: Progress }) {
  const units = course.units.filter((u) => u.course === c.id);
  const total = units.reduce((n, u) => n + unitBugs(u).length, 0);
  if (total === 0) return null;
  const rates = bugRates(progress.bugs, units);
  return (
    <section className="jt-panel jt-pad" aria-labelledby="jt-bug-rates">
      <div className="jt-eyebrow">Find the bug</div>
      <h3 id="jt-bug-rates" style={{ marginTop: "0.25rem" }}>Your fixes, by knowledge component</h3>
      <p className="jt-small" style={{ maxWidth: "50rem" }}>
        {total} practice problems in this course start from a solver with one planted error. A problem counts as fixed
        when the grader and every convergence test pass on the same code; hints are counted up to the fix. The record
        stays in this browser.
      </p>
      {rates.length === 0 ? <p className="jt-small jt-muted">No find-the-bug problem started yet.</p> : (
        <table className="jt-table jt-small">
          <thead><tr><th scope="col">Knowledge component</th><th scope="col">Fixed</th><th scope="col">Hints used on those</th></tr></thead>
          <tbody>
            {rates.map((r) => <tr key={r.kc}><td><code>{r.kc}</code></td><td>{r.fixed} of {r.total}</td><td>{r.hints}</td></tr>)}
          </tbody>
        </table>
      )}
    </section>
  );
}

/** Parsons problems put in order per knowledge component, over the ones checked in this browser. */
function ParsonsRates({ c, progress }: { c: CourseInfo; progress: Progress }) {
  const units = course.units.filter((u) => u.course === c.id);
  const total = units.reduce((n, u) => n + unitParsons(u).length, 0);
  if (total === 0) return null;
  const rates = parsonsRates(progress.parsons, units);
  return (
    <section className="jt-panel jt-pad" aria-labelledby="jt-parsons-rates">
      <div className="jt-eyebrow">Parsons problems</div>
      <h3 id="jt-parsons-rates" style={{ marginTop: "0.25rem" }}>Kernels put in order, by knowledge component</h3>
      <p className="jt-small" style={{ maxWidth: "50rem" }}>
        {total} practice problems in this course ask for the lines of a kernel in a working order. Every order that works
        was found by running all of them, so a check here needs no server. The record stays in this browser.
      </p>
      {rates.length === 0 ? <p className="jt-small jt-muted">No Parsons problem checked yet.</p> : (
        <table className="jt-table jt-small">
          <thead><tr><th scope="col">Knowledge component</th><th scope="col">In order</th><th scope="col">On the first check</th></tr></thead>
          <tbody>
            {rates.map((r) => <tr key={r.kc}><td><code>{r.kc}</code></td><td>{r.solved} of {r.total}</td><td>{r.firstTry}</td></tr>)}
          </tbody>
        </table>
      )}
    </section>
  );
}

/** Read a saved arrangement; anything malformed starts empty. */
function readOrder(saved: string, size: number): number[] {
  try {
    const v: unknown = JSON.parse(saved);
    return Array.isArray(v) && v.every((x) => Number.isInteger(x) && x >= 1 && x <= size) && new Set(v).size === v.length ? v as number[] : [];
  } catch {
    return [];
  }
}

/**
 * A Parsons problem: place lines from the pool into the kernel, move them, and
 * check the order against the measured set (no server needed). Once it works,
 * the whole program can also go through the grader, like any solution.
 */
function ParsonsProblem({ p, onSolved, record, onCheck }: {
  p: Problem; onSolved: (r: GradeResult) => void; record: ParsonsRecord | null; onCheck: (solved: boolean) => void;
}) {
  const z = p.parsons!;
  const [saved, setSaved] = useDraft(`parsons/${p.id}`, "[]");
  const order = readOrder(saved, z.pool.length);
  const [fb, setFb] = useState<ParsonsFeedback | null>(null);
  const [hints, setHints] = useState(0);
  const [result, setResult] = useState<GradeResult | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const { status } = useServer();
  const connected = status.kind === "connected";
  const setOrder = (o: number[]) => { setSaved(JSON.stringify(o)); setFb(null); setResult(null); };
  const left = displayOrder(p.id, z.pool).filter((i) => !order.includes(i));
  const move = (k: number, by: number) => {
    const o = [...order];
    [o[k], o[k + by]] = [o[k + by], o[k]];
    setOrder(o);
  };
  const check = () => {
    const f = parsonsFeedback(z.pool, z.n, z.accepted, order);
    setFb(f);
    if (f.kind !== "invalid") onCheck(f.kind === "solved");
  };
  const grade = async () => {
    if (!connected || busy) return;
    setBusy(true); setError(null);
    try {
      const r = await gradeCode(p.id, assemble(z, order));
      setResult(r);
      if (r.status === "passed") onSolved(r);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  };
  // Rows the last check judged: a working prefix in green, the first line that cannot follow in red.
  const rowClass = (k: number) => {
    if (!fb) return "";
    if (fb.kind === "prefix") return k < fb.good ? "good" : k === fb.good ? "bad" : "";
    if (fb.kind === "distractor") return order[k] === z.n + fb.distractor ? "bad" : "";
    return fb.kind === "solved" ? "good" : "";
  };
  const hintsReady = (record?.attempts ?? 0) > 0;
  const distractor = fb?.kind === "distractor" ? z.distractors[fb.distractor - 1] : null;

  return (
    <article className="jt-problem">
      <div className="jt-chips" style={{ marginBottom: "0.5rem" }}>
        <span className="jt-chip">{p.difficulty}</span>
        {p.kcs.map((k) => <span key={k} className="jt-chip kc">{k}</span>)}
        <span className="jt-chip info">define <code>{p.entry}</code></span>
        <span className="jt-chip advice" title="Put the lines in a working order; some lines on offer are wrong">
          Parsons: {z.n} lines to place, {z.distractors.length} wrong
        </span>
      </div>
      <Markdown text={p.prompt} />
      {p.samples.length > 0 && (
        <table className="jt-samples">
          <caption className="jt-small jt-muted">The reference solution on the cases every order was run on</caption>
          <tbody>
            {p.samples.map((s) => <tr key={s.call}><td><code>{s.call}</code></td><td><code>{s.result}</code></td></tr>)}
          </tbody>
        </table>
      )}
      <div className="jt-parsons">
        <div>
          <h4 id={`pk-${p.id}`}>Your kernel ({order.length} of {z.n} lines)</h4>
          <ol aria-labelledby={`pk-${p.id}`}>
            {z.head.map((l, i) => <li key={`h${i}`} className="fixed"><code>{l}</code></li>)}
            {order.length === 0 && <li className="gap">Pick lines on the right to place them here, in order.</li>}
            {order.map((i, k) => (
              <li key={i} className={rowClass(k)}>
                <code>{z.pool[i - 1]}</code>
                <button className="jt-btn ghost jt-small" disabled={k === 0} onClick={() => move(k, -1)} aria-label={`Move line ${k + 1} up`}>↑</button>
                <button className="jt-btn ghost jt-small" disabled={k === order.length - 1} onClick={() => move(k, 1)} aria-label={`Move line ${k + 1} down`}>↓</button>
                <button className="jt-btn ghost jt-small" onClick={() => setOrder(order.filter((x) => x !== i))} aria-label={`Remove line ${k + 1}`}>✕</button>
              </li>
            ))}
            {z.tail.map((l, i) => <li key={`t${i}`} className="fixed"><code>{l}</code></li>)}
          </ol>
        </div>
        <div>
          <h4 id={`pp-${p.id}`}>Lines to place</h4>
          <ol aria-labelledby={`pp-${p.id}`}>
            {left.length === 0 && <li className="gap">Every line is placed.</li>}
            {left.map((i) => (
              <li key={i}>
                <button className="jt-btn ghost jt-small" onClick={() => setOrder([...order, i])} aria-label={`Place: ${z.pool[i - 1].trim()}`}>+</button>
                <code>{z.pool[i - 1]}</code>
              </li>
            ))}
          </ol>
        </div>
      </div>
      <div className="jt-row">
        <button className="jt-btn primary" disabled={order.length === 0} onClick={check}>Check the order</button>
        {fb?.kind === "solved" && (
          <button className="jt-btn" disabled={!connected || busy} onClick={grade}
            title={connected ? "Grade the whole program, as for any solution" : "Needs tutor serve"}>
            {busy ? "Grading…" : "Run it through the grader"}
          </button>
        )}
        {hints < p.hints.length && (
          <button className="jt-btn ghost jt-small" disabled={!hintsReady} onClick={() => setHints((h) => h + 1)}
            title={hintsReady ? undefined : "Check an order first"}>
            {hints === 0 ? "Show a hint" : "Another hint"} ({hints}/{p.hints.length})
          </button>
        )}
        {order.length > 0 && <button className="jt-btn ghost jt-small" onClick={() => setOrder([])}>Start over</button>}
      </div>
      <div aria-live="polite">
        {fb?.kind === "count" && (
          <div className="jt-callout hint"><span className="tag">Not yet</span>
            <div>A working order uses exactly {fb.need} lines; yours has {order.length}.</div></div>
        )}
        {fb?.kind === "prefix" && (
          <div className="jt-callout mis"><span className="tag">Not this order</span>
            <div>
              {fb.good === 0 ? "No working order starts with your first line." :
                `Your first ${fb.good} line${fb.good === 1 ? "" : "s"} can start a working order; line ${fb.good + 1} cannot come next.`}
            </div></div>
        )}
        {distractor && (
          <div className="jt-callout mis"><span className="tag">A wrong line</span>
            <div>
              <Code src={distractor && z.pool[distractor.index - 1].trim()} />
              {md(distractor.misconception)}
            </div></div>
        )}
        {fb?.kind === "solved" && (
          <div className="jt-callout ok"><span className="tag">Works</span>
            <div>
              This order is one of {z.accepted.length} that work{z.accepted.length === 1 ? "s" : ""} on the cases
              {record ? `, found on check ${record.attempts}` : ""}.
              {z.accepted.length > 1 && " Lines that do not depend on each other can swap places."}
            </div></div>
        )}
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

/** The convergence tests' measurements on the learner's code, with what each failing one measures. */
function BugTests({ bug, readings, errors }: { bug: Bug; readings: BugReading[]; errors: string[] }) {
  const failing = bug.tests.filter((_, i) => !readings[i]?.passed);
  return (
    <div className={`jt-callout ${failing.length ? "mis" : "ok"}`} aria-live="polite">
      <span className="tag">{failing.length ? `${failing.length} of ${bug.tests.length} tests fail` : "Every test passes"}</span>
      <div>
        <table className="jt-table jt-small" style={{ margin: "0 0 0.4rem" }}>
          <caption className="jt-muted" style={{ textAlign: "left", captionSide: "top" }}>Convergence tests on the code in the editor</caption>
          <thead><tr><th scope="col">Test</th><th scope="col">Measured</th><th scope="col">A correct solver</th><th scope="col" /></tr></thead>
          <tbody>
            {bug.tests.map((t, i) => {
              const r = readings[i];
              return (
                <tr key={t.name}>
                  <td>{md(t.name)}</td>
                  <td>{r?.value === null || r === undefined ? (errors[i] || "no reading") : String(r.value)}</td>
                  <td>{t.expect[0]} to {t.expect[1]}</td>
                  <td>{r?.passed ? "pass" : "fail"}</td>
                </tr>
              );
            })}
          </tbody>
        </table>
        {failing.map((t) => <div key={t.name} style={{ marginTop: "0.3rem" }}><strong>{md(t.name)}:</strong> {md(t.explain)}</div>)}
        <details className="jt-small" style={{ marginTop: "0.4rem" }}>
          <summary>The tests' code (each runs after yours, in a fresh Julia)</summary>
          {bug.tests.map((t) => <Code key={t.name} src={t.code} />)}
        </details>
      </div>
    </div>
  );
}

/** Once fixed: the planted line next to the reference's, and the belief it models. */
function BugFixed({ bug, record }: { bug: Bug; record: BugRecord }) {
  return (
    <div className="jt-callout ok">
      <span className="tag">Fixed</span>
      <div>
        <div className="jt-small">
          The grader and every convergence test passed on the same code, after {record.runs} test
          run{record.runs === 1 ? "" : "s"} and {record.hints} hint{record.hints === 1 ? "" : "s"}. The planted line was
        </div>
        <Code src={bug.planted} />
        <div className="jt-small">and the reference has</div>
        <Code src={bug.fixed} />
        <div style={{ marginTop: "0.3rem" }}>{md(bug.misconception)}</div>
      </div>
    </div>
  );
}

function ProblemPanel({ p, env, onSolved, bugRecord, onBug }: {
  p: Problem; env: string; onSolved: (r: GradeResult) => void;
  bugRecord: BugRecord | null; onBug: (what: "run" | "hint" | "fixed") => void;
}) {
  const [code, setCode] = useDraft(`problem/${p.id}`, p.starter);
  const { status } = useServer();
  const [result, setResult] = useState<GradeResult | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [hints, setHints] = useState(0);
  const [tests, setTests] = useState<{ readings: BugReading[]; errors: string[] } | null>(null);
  const connected = status.kind === "connected";
  const canRunTests = connected && status.envs.includes(env);
  const bug = p.bug;

  // Every convergence test, one fresh run each, on `src`; returns whether all passed.
  const runTests = async (src: string): Promise<boolean> => {
    if (!bug) return false;
    const readings: BugReading[] = [];
    const errors: string[] = [];
    for (const t of bug.tests) {
      try {
        const r = await runCode(bugTestCode(src, t), env);
        readings.push(reading(t, r.output));
        errors.push(r.ok ? "" : r.output.split("\n").find((l) => l.startsWith("ERROR")) ?? "the run ended with an error");
      } catch (e) {
        readings.push({ name: t.name, value: null, passed: false });
        errors.push((e as Error).message);
      }
    }
    setTests({ readings, errors });
    onBug("run");
    return readings.every((x) => x.passed);
  };

  const grade = async () => {
    if (!connected || busy) return;
    setBusy(true); setError(null);
    try {
      const src = code;
      const r = await gradeCode(p.id, src);
      setResult(r);
      if (r.status === "passed") onSolved(r);
      // Fixed = the grader and every test pass on the same code.
      if (bug && canRunTests && r.status === "passed" && await runTests(src)) onBug("fixed");
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  };
  const testOnly = async () => {
    if (!canRunTests || busy) return;
    setBusy(true); setError(null);
    try { await runTests(code); } finally { setBusy(false); }
  };
  const hintsReady = !bug || hintsOpen(bugRecord?.runs ?? 0, canRunTests);
  const moreHint = () => { setHints((h) => h + 1); if (bug) onBug("hint"); };

  const how = p.compare === "isapprox" ? `isapprox (rtol ${p.rtol})` : "isequal";
  return (
    <article className="jt-problem">
      <div className="jt-chips" style={{ marginBottom: "0.5rem" }}>
        <span className="jt-chip">{p.difficulty}</span>
        {p.kcs.map((k) => <span key={k} className="jt-chip kc">{k}</span>)}
        <span className="jt-chip info">define <code>{p.entry}</code></span>
        {bug && <span className="jt-chip advice" title="The code in the editor is the reference with one line changed">find the bug: one line is wrong</span>}
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
        {bug && (
          <button className="jt-btn" disabled={!canRunTests || busy} onClick={testOnly}
            title={canRunTests ? "Run every convergence test on the code in the editor" : `Needs tutor serve with the ${env} environment`}>
            Run the convergence tests
          </button>
        )}
        {hints < p.hints.length && (
          <button className="jt-btn ghost jt-small" disabled={!hintsReady} onClick={moreHint}
            title={hintsReady ? undefined : "Run the convergence tests first: what they measure is the first hint"}>
            {hints === 0 ? "Show a hint" : "Another hint"} ({hints}/{p.hints.length})
          </button>
        )}
        {code !== p.starter && <button className="jt-btn ghost jt-small" onClick={() => setCode(p.starter)}>Back to the starter</button>}
      </div>
      {bug && tests && <BugTests bug={bug} readings={tests.readings} errors={tests.errors} />}
      {p.hints.slice(0, hints).map((h, i) => (
        <div key={i} className="jt-callout hint"><span className="tag">Hint {i + 1}</span><div>{md(h)}</div></div>
      ))}
      {busy && <Output result={null} error={null} running />}
      {error && <Output result={null} error={error} running={false} />}
      {result && !busy && <Feedback r={result} />}
      {bug && bugRecord?.fixed && <BugFixed bug={bug} record={bugRecord} />}
    </article>
  );
}
