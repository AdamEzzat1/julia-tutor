import { Report } from "../components/Report";
import { data } from "../data";

export function HeroView() {
  const p = data.projects[0];
  const checks = data.lessons.reduce((n, l) => n + l.checks.length, 0);
  const mutants = Object.values(p.mutants).flat();
  const featured = p.fixtures.find((f) => f.name === "pvar_binding-mutates-bindings") ?? p.fixtures[0];
  // Show the head of the report: the part that answers "where do I start?".
  const head = featured.golden.split("\n").slice(0, 12).join("\n");

  return (
    <div className="jt-grid" style={{ gap: "1.5rem" }}>
      <section className="jt-hero">
        <div className="jt-hero-grid">
          <div>
            <div className="jt-eyebrow"><span className="jt-pips" aria-hidden="true"><i /><i /><i /></span>&nbsp; Symbolic tutor · Julia {data.julia} LTS</div>
            <h2 style={{ marginTop: "0.6rem" }}>Feedback you can <em>trace back</em> to a rule, a test or a measurement.</h2>
            <p className="lede">
              julia-tutor teaches Julia through research-grade projects with holes in them. Every hint comes from a
              rule with a stated false-positive risk, every diagnosis from measured test runs, and every lesson answer
              from actually running the code. No language model sits in the feedback loop.
            </p>
            <div className="jt-chips" style={{ marginTop: "1rem" }}>
              <a className="jt-btn primary" href="lessons.html" style={{ textDecoration: "none" }}>Try a lesson</a>
              <a className="jt-btn" href="explain.html" style={{ textDecoration: "none" }}>See explain at work</a>
            </div>
            <div className="jt-stats">
              <div className="jt-stat"><b>{checks}</b><span>predict-the-output checks, keys verified</span></div>
              <div className="jt-stat"><b>{data.rules.length}</b><span>checker rules with hint ladders</span></div>
              <div className="jt-stat"><b>{p.holes.length}</b><span>holes over {p.stages.length} fading stages</span></div>
              <div className="jt-stat"><b>{mutants.filter((m) => m.caught).length}/{mutants.length}</b><span>wrong bodies caught by tests</span></div>
            </div>
          </div>
          <Report text={head} title={`explain · ${featured.name}`} wrap />
        </div>
      </section>

      <section className="jt-loop" aria-label="How it works">
        {[
          ["01", "Fill a hole", "A starter package has functions with TODO bodies. The docstring is the specification."],
          ["02", "Run the tests", "Behavioural tests, exact where possible, tolerances derived where not, in a fresh process."],
          ["03", "Explain", "Failures, checker findings and measurements are joined through the measured test-to-hole map."],
          ["04", "Learn", "Short lessons fix the misconception behind the bug, and spaced review keeps it fixed."],
        ].map(([n, t, d]) => (
          <div key={n} className="jt-panel step">
            <div className="n">{n}</div>
            <h4>{t}</h4>
            <p>{d}</p>
          </div>
        ))}
      </section>
    </div>
  );
}
