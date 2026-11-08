import { useState } from "react";
import { Code } from "../components/Code";
import { inline } from "../components/Prose";
import { data, type Rule } from "../data";

const SEVERITIES = ["all", "WARN", "ADVICE"] as const;

export function RulesView() {
  const [sev, setSev] = useState<(typeof SEVERITIES)[number]>("all");
  const rules = data.rules.filter((r) => sev === "all" || r.severity === sev);
  return (
    <div>
      <div className="jt-toolbar">
        <div className="jt-filter" role="group" aria-label="Severity" style={{ margin: 0 }}>
          {SEVERITIES.map((s) => (
            <button key={s} className="jt-btn" aria-pressed={sev === s} onClick={() => setSev(s)}>
              {s === "all" ? `All ${data.rules.length}` : s}
            </button>
          ))}
        </div>
        <span className="jt-small jt-muted">WARN sets the exit code · ADVICE never does (invariant 2)</span>
      </div>
      <div className="jt-rules">
        {rules.map((r) => <RuleCard key={r.id} rule={r} />)}
      </div>
    </div>
  );
}

function RuleCard({ rule }: { rule: Rule }) {
  const [shown, setShown] = useState(1);
  return (
    <article className="jt-panel jt-pad jt-rule">
      <div className="jt-toolbar" style={{ margin: 0 }}>
        <span className="jt-rule-id">{rule.id}</span>
        <span className={`jt-chip ${rule.severity === "ADVICE" ? "advice" : "warn"}`}>{rule.severity}</span>
      </div>
      <h3 style={{ margin: 0 }}>{rule.name.replace(/-/g, " ")}</h3>
      <div className="jt-chips"><span className="jt-chip kc">{rule.kc}</span></div>
      {rule.example && (
        <div>
          <Code src={rule.example.code} />
          {rule.example.message && (
            <div className="jt-small" style={{ fontFamily: "var(--jt-mono)", color: rule.severity === "ADVICE" ? "var(--jt-amber)" : "var(--jt-red)" }}>
              example.jl:{rule.example.line}: {rule.severity} {rule.id} {rule.example.message}
            </div>
          )}
        </div>
      )}
      <div>
        <div className="jt-eyebrow" style={{ marginBottom: "0.4rem" }}>Hint ladder · level 1 never gives the answer</div>
        <ol className="jt-ladder">
          {rule.hints.slice(0, shown).map((h, i) => <li key={i}><span>{inline(h)}</span></li>)}
        </ol>
        {shown < rule.hints.length && (
          <button className="jt-btn ghost jt-small" style={{ marginTop: "0.4rem" }} onClick={() => setShown(shown + 1)}>
            Show hint {shown + 1} →
          </button>
        )}
      </div>
      <dl className="jt-dl">
        <dt>FP risk</dt><dd>{inline(rule.fp_risk)}</dd>
        <dt>Confirmed by</dt><dd>{inline(rule.measured_by)}</dd>
      </dl>
    </article>
  );
}
