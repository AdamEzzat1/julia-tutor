import { useState } from "react";
import { Code } from "../components/Code";
import { inline, Spec } from "../components/Prose";
import { Report } from "../components/Report";
import { data } from "../data";

export function ExplainView() {
  const project = data.projects[0];
  const [name, setName] = useState(project.fixtures[0]?.name ?? "");
  const f = project.fixtures.find((x) => x.name === name) ?? project.fixtures[0];
  const hole = project.holes.find((h) => h.id === f.hole)!;
  const start = f.golden.split("\n").find((l) => l.startsWith("Start here:")) ?? "";
  const hit = f.expect_start === "JT000" ? start.includes("does not parse") : start.includes(`hole \`${f.expect_start}\``);

  return (
    <div className="jt-split">
      <nav className="jt-panel jt-nav" aria-label="Fixtures">
        {project.stages.map((s) => (
          <div key={s}>
            <div className="jt-eyebrow" style={{ padding: "0.5rem 0.7rem 0.2rem" }}>Stage {s}</div>
            {project.fixtures.filter((x) => x.stage === s).map((x) => (
              <button key={x.name} aria-current={x.name === f.name} onClick={() => setName(x.name)}>
                <span className="t">{x.hole}</span>
                <span className="s">{x.name.replace(`${x.hole}-`, "").replace(/-/g, " ")}</span>
              </button>
            ))}
          </div>
        ))}
      </nav>

      <div className="jt-grid" style={{ gap: "1.1rem" }}>
        <section className="jt-panel jt-pad">
          <div className="jt-toolbar">
            <div className="jt-chips">
              <span className="jt-chip kc">{hole.kc}</span>
              <span className="jt-chip">stage {f.stage}</span>
              <span className="jt-chip fail">misconception · {f.misconception}</span>
            </div>
            <span className={`jt-chip ${hit ? "pass" : "fail"}`}>
              {hit ? "✓" : "✗"} explain points at {f.expect_start === "JT000" ? "the parse error" : f.expect_start}
            </span>
          </div>
          <h3>{inline(f.description.charAt(0).toUpperCase() + f.description.slice(1))}</h3>
          <p className="jt-muted jt-small">
            The reference solution with exactly one hole replaced by this body. Every other hole is correct,
            so the report below shows how explain isolates one misconception.
          </p>
          <div className="jt-eyebrow" style={{ marginTop: "0.6rem" }}>The student's body for <code>{hole.id}</code></div>
          <Code src={f.body} />
          <details>
            <summary className="jt-small" style={{ cursor: "pointer", color: "var(--jt-blue)" }}>
              The specification it was written against (the hole's docstring)
            </summary>
            <div style={{ marginTop: "0.5rem" }}><Spec text={hole.spec} /></div>
          </details>
        </section>

        <Report text={f.golden} title={`tutor explain ${project.name} · ${f.name}`} />

        <p className="jt-small jt-muted">
          Reports are byte-for-byte the committed golden outputs. <code>tutor fixtures {project.name} --check</code> re-runs
          every fixture on the pinned Julia {data.julia} and fails on any difference. Measurements are single-threaded,
          after warm-up; JET is opt-in and not part of the goldens.
        </p>
      </div>
    </div>
  );
}
