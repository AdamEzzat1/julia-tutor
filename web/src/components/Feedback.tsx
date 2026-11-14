import type { GradeResult } from "../server";
import { md } from "./Markdown";
import { RUNG_MARK, type Ladder, type LadderRecord, type Rung } from "../ladder";

// Renders the grader's result. Every sentence comes from Practice.assess in
// Julia (the same text `tutor practice` prints); this only lays it out.

const MARK = { pass: "✓", warn: "!", fail: "✗", info: "·" } as const;

export function fmtNs(ns: number): string {
  if (ns < 1e3) return `${ns.toFixed(1)} ns`;
  if (ns < 1e6) return `${(ns / 1e3).toFixed(1)} μs`;
  if (ns < 1e9) return `${(ns / 1e6).toFixed(1)} ms`;
  return `${(ns / 1e9).toFixed(2)} s`;
}

export function fmtBytes(b: number): string {
  if (b < 1024) return `${b} B`;
  if (b < 1024 ** 2) return `${(b / 1024).toFixed(1)} KiB`;
  return `${(b / 1024 ** 2).toFixed(1)} MiB`;
}

const HEADLINE: Record<GradeResult["status"], string> = {
  passed: "Correct",
  failed: "Not yet: some cases fail",
  "load-error": "Your code does not run",
  "no-entry": "Missing function",
  timeout: "Timed out",
  crash: "The grader crashed",
  "internal-error": "A bug in this problem",
};

const OVERALL = { excellent: "Performance: excellent", good: "Performance: good", "needs-work": "Performance: needs work" } as const;

export function Feedback({ r, best }: { r: GradeResult; best?: LadderRecord | null }) {
  const perf = r.performance;
  return (
    <section className={`jt-feedback ${r.status === "passed" ? "ok" : "bad"}`} aria-live="polite" aria-label="Grading result">
      <div className="jt-toolbar" style={{ marginBottom: "0.6rem" }}>
        <h4 style={{ margin: 0 }}>{HEADLINE[r.status]}</h4>
        <div className="jt-chips">
          {r.correctness && (
            <span className={`jt-chip ${r.correctness.passed === r.correctness.total ? "pass" : "fail"}`}>
              {r.correctness.passed}/{r.correctness.total} cases
            </span>
          )}
          {perf && (
            <span className={`jt-chip ${perf.overall === "excellent" ? "pass" : perf.overall === "good" ? "advice" : "fail"}`}>
              {OVERALL[perf.overall]}
            </span>
          )}
          <span className="jt-chip" title="Wall clock, including starting Julia and compiling">{r.seconds} s</span>
        </div>
      </div>
      <ul className="jt-fb-list">
        {r.feedback.map((f, i) => (
          <li key={i} className={f.level}>
            <span className="mark" aria-hidden="true">{MARK[f.level]}</span>
            <div>
              <div className="t">{md(f.title)}</div>
              {f.detail && (f.detail.includes("\n") ? <pre className="jt-output">{f.detail}</pre> : <div className="d">{md(f.detail)}</div>)}
            </div>
          </li>
        ))}
      </ul>
      {r.correctness && r.correctness.failures.length > 1 && (
        <details>
          <summary className="jt-small" style={{ cursor: "pointer" }}>More failing cases</summary>
          {r.correctness.failures.slice(1).map((f) => (
            <pre key={f.case} className="jt-output">{`${f.input}\n  expected: ${f.expected}\n  got:      ${f.got}   (${f.reason})`}</pre>
          ))}
        </details>
      )}
      {perf?.sizes && (
        <table className="jt-perf">
          <thead>
            <tr><th>n</th><th>your time</th><th>reference</th><th>your memory</th><th>reference</th></tr>
          </thead>
          <tbody>
            {perf.sizes.map((s) => (
              <tr key={s.n}>
                <td>{s.n.toLocaleString("en-US")}</td>
                <td>{fmtNs(s.sub_ns)}</td><td>{fmtNs(s.ref_ns)}</td>
                <td>{fmtBytes(s.sub_bytes)}</td><td>{fmtBytes(s.ref_bytes)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
      {r.ladder && <LadderView l={r.ladder} best={best ?? null} />}
      {r.findings.length > 0 && (
        <div style={{ marginTop: "0.7rem" }}>
          <div className="jt-eyebrow">Static checker</div>
          <ul className="jt-fb-list">
            {r.findings.map((f, i) => (
              <li key={i} className="info">
                <span className="mark" aria-hidden="true">·</span>
                <div><div className="t">{f.rule} · line {f.line}</div><div className="d">{f.message}</div></div>
              </li>
            ))}
          </ul>
        </div>
      )}
      {perf?.sizes && (
        <p className="jt-small jt-muted" style={{ margin: "0.6rem 0 0" }}>
          Times are the minimum over interleaved samples of your function and the reference in the same process, so
          the ratio holds on any machine; absolute numbers are your machine's.
        </p>
      )}
    </section>
  );
}

// Not reached on rung 1 is a wrong answer (red); above it, a direction to work in (amber).
const rungClass = (x: Rung, i: number) =>
  x.state === "reached" ? "pass" : x.state === "not-reached" ? (i === 0 ? "fail" : "warn") : "info";

function LadderView({ l, best }: { l: Ladder; best: LadderRecord | null }) {
  const better = best !== null && best.climbed > l.climbed;
  return (
    <div className="jt-perfladder" style={{ marginTop: "0.8rem" }}>
      <div className="jt-eyebrow">
        Performance ladder · {l.climbed} of {l.offered} rung{l.offered === 1 ? "" : "s"}
        {better ? ` · best in this browser: ${best.climbed} of ${best.offered}` : ""}
      </div>
      <ul className="jt-fb-list" aria-label="Performance ladder rungs">
        {l.rungs.map((x, i) => (
          <li key={x.id} className={`${rungClass(x, i)}${x.state === "not-offered" ? " off" : ""}`}>
            <span className="mark" aria-hidden="true">{RUNG_MARK[x.state]}</span>
            <div>
              <div className="t">
                {i + 1}. {x.title}
                <span className="jt-sr"> ({x.state.replace("-", " ")})</span>
                {x.state === "not-offered" ? <span className="jt-muted"> · not offered</span> : null}
              </div>
              <div className="d">{md(x.detail)}</div>
            </div>
          </li>
        ))}
      </ul>
      <p className="jt-small jt-muted" style={{ margin: "0.5rem 0 0" }}>
        Rungs are climbed in order. The best climb is kept in this browser only: nothing is sent, and there is no ranking.
      </p>
    </div>
  );
}
