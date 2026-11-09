import { useState } from "react";
import { Code } from "../components/Code";
import { Markdown, md } from "../components/Markdown";
import { inline } from "../components/Prose";
import { questionState, type Question } from "../course";
import { commands, guided, orderedProjects, type Behaviour, type GuidedProject, type Milestone } from "../guided";

// Guided build projects: the student writes the package and its tests from
// these specs; `tutor guided check` (local, in the sandbox) grades the code
// against hidden acceptance tests and the tests against seeded faults. The
// site shows the specs, hint ladders and concept questions; it runs nothing.

function readProject(): string | null {
  try {
    return new URLSearchParams(window.location.search).get("project");
  } catch {
    return null;
  }
}

function writeProject(name: string | null) {
  try {
    const u = new URL(window.location.href);
    if (name) u.searchParams.set("project", name);
    else u.searchParams.delete("project");
    window.history.replaceState(null, "", u.toString());
  } catch {
    /* static preview without history: ignore */
  }
}

export function GuidedView() {
  const [name, setName] = useState<string | null>(readProject());
  const p = guided.projects.find((x) => x.name === name) ?? null;
  const go = (n: string | null) => {
    setName(n);
    writeProject(n);
  };
  return p ? <ProjectPage p={p} back={() => go(null)} /> : <Overview open={go} />;
}

function StatusChip({ p }: { p: GuidedProject }) {
  return p.status === "ready" ? <span className="jt-chip pass">ready</span> : <span className="jt-chip">spec only</span>;
}

function Overview({ open }: { open: (n: string) => void }) {
  return (
    <div>
      <p className="jt-muted jt-small">
        {guided.projects.length} projects · {guided.projects.filter((p) => p.status === "ready").length} ready to check
        · Julia {guided.julia}. A check needs your own julia-tutor checkout: it runs your code in the sandbox container.
      </p>
      <div className="jt-rules">
        {orderedProjects().map((p) => (
          <article key={p.name} className="jt-panel jt-pad jt-rule">
            <div className="jt-toolbar" style={{ margin: 0 }}>
              <span className="jt-rule-id">{p.name}</span>
              <StatusChip p={p} />
              <span className="jt-chip">{p.env}</span>
            </div>
            <h3 style={{ margin: 0 }}>{p.title.split(": ").slice(1).join(": ") || p.title}</h3>
            <p className="jt-small" style={{ margin: 0 }}>{inline(p.summary)}</p>
            <div className="jt-chips">{p.packages.map((k) => <span key={k} className="jt-chip kc">{k}</span>)}</div>
            <div className="jt-small jt-muted">
              {p.milestones.length} milestones · {p.host_ok ? "host or container" : "container only on Windows hosts"}
            </div>
            <button className="jt-btn" onClick={() => open(p.name)}>Read the milestones →</button>
          </article>
        ))}
      </div>
    </div>
  );
}

function ProjectPage({ p, back }: { p: GuidedProject; back: () => void }) {
  const [open, setOpen] = useState<number>(0);
  return (
    <div>
      <div className="jt-toolbar">
        <button className="jt-btn ghost jt-small" onClick={back}>← All projects</button>
        <StatusChip p={p} />
        <span className="jt-chip">env {p.env}</span>
      </div>
      <h2 style={{ marginTop: 0 }}>{p.title}</h2>
      <Markdown text={p.summary} />
      {p.reading && <Markdown text={p.reading} />}
      <div className="jt-eyebrow" style={{ marginTop: "1rem" }}>Run it (from the julia-tutor folder)</div>
      <Code src={commands(p).join("\n")} />
      {p.status !== "ready" && (
        <p className="jt-small jt-muted">
          This project is specified but not built yet: its reference, acceptance tests and seeded faults do not
          exist, so `tutor guided check` refuses it.
        </p>
      )}
      {p.milestones.map((m) => (
        <MilestoneBlock key={m.id} m={m} open={open === m.id} toggle={() => setOpen(open === m.id ? -1 : m.id)} />
      ))}
    </div>
  );
}

function MilestoneBlock({ m, open, toggle }: { m: Milestone; open: boolean; toggle: () => void }) {
  return (
    <section className="jt-panel jt-pad" style={{ marginTop: "0.8rem" }}>
      <button className="jt-btn ghost" aria-expanded={open} onClick={toggle} style={{ width: "100%", textAlign: "left" }}>
        Milestone {m.id}: {m.title}
      </button>
      {open && (
        <div style={{ marginTop: "0.6rem" }}>
          <Markdown text={m.goal} />
          {m.api.length > 0 && (
            <>
              <div className="jt-eyebrow">API to write</div>
              <Code src={m.api.map((a) => a.signature + (a.doc ? "\n    # " + a.doc.replace(/\n/g, "\n    # ") : "")).join("\n")} />
            </>
          )}
          {m.behaviours.length > 0 && <div className="jt-eyebrow" style={{ marginTop: "0.6rem" }}>Behaviour</div>}
          {m.behaviours.map((b) => <BehaviourBlock key={b.id} b={b} covered={m.must_cover.includes(b.id)} />)}
          {m.must_cover.length > 0 && (
            <p className="jt-small jt-muted">
              Your tests must cover {m.must_cover.map((c) => `\`${c}\``).join(", ")}: the check runs them against{" "}
              {m.mutants > 0 ? `${m.mutants} seeded faults` : "seeded faults"} in a correct implementation and needs{" "}
              {Math.round(100 * m.min_score)}% caught.
            </p>
          )}
          {m.perf_entry && (
            <p className="jt-small jt-muted">
              <code>{m.perf_entry}</code> is also graded against the reference for speed, allocations, growth with
              input size and type stability, once the acceptance tests pass.
            </p>
          )}
          {m.questions.map((q, k) => <GuidedQuestion key={k} q={q} number={k + 1} total={m.questions.length} />)}
        </div>
      )}
    </section>
  );
}

function BehaviourBlock({ b, covered }: { b: Behaviour; covered: boolean }) {
  const [shown, setShown] = useState(0);
  const [tests, setTests] = useState(0);
  return (
    <div style={{ margin: "0.5rem 0" }}>
      <div className="jt-chips" style={{ marginBottom: "0.2rem" }}>
        <span className="jt-rule-id">{b.id}</span>
        <span className="jt-chip kc">{b.kc}</span>
        {covered && <span className="jt-chip">test it</span>}
      </div>
      <div>{md(b.spec)}</div>
      {shown > 0 && <ol className="jt-ladder">{b.hints.slice(0, shown).map((h, i) => <li key={i}><span>{inline(h)}</span></li>)}</ol>}
      {tests > 0 && (
        <ol className="jt-ladder">{b.test_hints.slice(0, tests).map((h, i) => <li key={i}><span>What to test: {inline(h)}</span></li>)}</ol>
      )}
      {(shown > 0 || tests > 0) && (
        <p style={{ color: "var(--jt-muted)", fontSize: "0.85em", margin: "0.2rem 0" }}>The site shows the first hint only. Later ones come from <code>tutor guided check</code>, one level per check that still misses this behaviour.</p>
      )}
      <div className="jt-toolbar" style={{ margin: "0.2rem 0 0" }}>
        {shown < b.hints.length && (
          <button className="jt-btn ghost jt-small" onClick={() => setShown(shown + 1)}>Code hint {shown + 1} →</button>
        )}
        {covered && tests < b.test_hints.length && (
          <button className="jt-btn ghost jt-small" onClick={() => setTests(tests + 1)}>Test hint {tests + 1} →</button>
        )}
      </div>
    </div>
  );
}

const LETTERS = "ABCDEF";

/** Same behaviour as the course's questions: pick until right, misconception on each wrong pick. */
function GuidedQuestion({ q, number, total }: { q: Question; number: number; total: number }) {
  const [picks, setPicks] = useState<number[]>([]);
  const st = questionState(q, picks);
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
            <button key={i} className={`jt-option ${cls}`} disabled={st.done || picks.includes(i)}
                    onClick={() => !st.done && !picks.includes(i) && setPicks([...picks, i])}>
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
          <div>{md(q.explain)}</div>
        </div>
      )}
    </div>
  );
}
