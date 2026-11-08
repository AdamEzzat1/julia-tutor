import { useMemo, useState } from "react";
import { Spec } from "../components/Prose";
import { data, shortTestset } from "../data";
import { rankByOchiai } from "../models";

// The measured test-to-hole map as a matrix, plus an Ochiai playground: mark
// failing testsets (or "open" a hole to see which testsets it breaks) and watch
// the same ranking explain uses.
export function HoleMapView() {
  const project = data.projects[0];
  const [stage, setStage] = useState(project.stages[project.stages.length - 1]);
  const holes = project.holes.filter((h) => h.stage <= stage);
  const [failing, setFailing] = useState<Set<string>>(new Set());
  const [opened, setOpened] = useState<string | null>(null);
  const [focus, setFocus] = useState<string>(holes[0]?.id ?? "");

  const toggle = (t: string) => {
    setOpened(null);
    setFailing((s) => { const n = new Set(s); n.has(t) ? n.delete(t) : n.add(t); return n; });
  };
  const open = (h: string) => {
    if (opened === h) { setOpened(null); setFailing(new Set()); return; }
    setOpened(h); setFocus(h);
    setFailing(new Set(project.deps[h] ?? []));
  };
  const ranking = useMemo(() => rankByOchiai(project.deps, failing, holes.map((h) => h.id)), [failing, holes, project.deps]);
  const focused = project.holes.find((h) => h.id === focus) ?? holes[0];
  const mutants = (id: string) => project.mutants[id] ?? [];

  return (
    <div className="jt-grid" style={{ gap: "1.1rem" }}>
      <section className="jt-panel jt-pad">
        <div className="jt-toolbar">
          <div>
            <div className="jt-eyebrow">Measured, not inferred</div>
            <h3 style={{ marginTop: "0.25rem" }}>Which testsets fail when exactly one hole is opened</h3>
          </div>
          <div className="jt-filter" role="group" aria-label="Stage" style={{ margin: 0 }}>
            {project.stages.map((s) => (
              <button key={s} className="jt-btn" aria-pressed={s === stage}
                onClick={() => { setStage(s); setOpened(null); setFailing(new Set()); }}>
                Stage {s}
              </button>
            ))}
          </div>
        </div>
        <p className="jt-small jt-muted" style={{ maxWidth: "52rem" }}>
          Each column is a run of the full test suite on the reference with only that hole replaced by its TODO body,
          in a fresh process. Click a hole to open it; click a testset to mark it failing yourself.
          The ranking on the right is the Ochiai score explain uses to say where to start.
        </p>

        <div className="jt-matrix-wrap">
          <table className="jt-matrix">
            <thead>
              <tr>
                <th style={{ textAlign: "left", paddingLeft: 0 }}>testset</th>
                {holes.map((h) => (
                  <th key={h.id} className={opened === h.id ? "jt-col-on" : ""}>
                    <button aria-pressed={opened === h.id} onClick={() => open(h.id)} title={`Open ${h.id}`}>
                      <span>{h.id}</span>
                      <span className="jt-muted" style={{ fontSize: "0.65rem" }}>stage {h.stage}</span>
                    </button>
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {project.testsets.map((t) => {
                const isFailing = failing.has(t);
                return (
                  <tr key={t} className={isFailing ? "failing" : ""}>
                    <th scope="row">
                      <button className="jt-btn ghost jt-small" style={{ padding: "0.15rem 0.4rem", color: "inherit" }}
                        aria-pressed={isFailing} onClick={() => toggle(t)}>
                        {isFailing ? "✗ " : ""}{shortTestset(t)}
                      </button>
                    </th>
                    {holes.map((h) => {
                      const dep = (project.deps[h.id] ?? []).includes(t);
                      return (
                        <td key={h.id} className={opened === h.id ? "jt-col-on" : ""}>
                          <span className={`jt-cell ${dep ? "dep" : ""} ${dep && isFailing ? "hot" : ""} ${dep && failing.size > 0 && !isFailing ? "cool" : ""}`}
                            aria-label={dep ? `${shortTestset(t)} depends on ${h.id}` : undefined} />
                        </td>
                      );
                    })}
                  </tr>
                );
              })}
              <tr>
                <th scope="row" className="jt-muted jt-small" style={{ paddingTop: "0.6rem" }}>mutants caught</th>
                {holes.map((h) => {
                  const m = mutants(h.id);
                  const caught = m.filter((x) => x.caught).length;
                  return (
                    <td key={h.id} className={opened === h.id ? "jt-col-on" : ""}>
                      <span className={`jt-chip ${caught === m.length ? "pass" : "fail"}`} style={{ margin: "0.4rem 0" }}>
                        {caught}/{m.length}
                      </span>
                    </td>
                  );
                })}
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <div className="jt-two">
        <section className="jt-panel jt-pad" aria-live="polite">
          <div className="jt-eyebrow">Ochiai ranking · {failing.size} failing testset{failing.size === 1 ? "" : "s"}</div>
          <h3 style={{ marginTop: "0.25rem" }}>Where explain would say to start</h3>
          {failing.size === 0 ? (
            <p className="jt-muted jt-small">Open a hole or mark testsets as failing to see the ranking.</p>
          ) : (
            <div className="jt-rank" style={{ marginTop: "0.6rem" }}>
              {ranking.map((r, i) => (
                <div key={r.hole} className={`jt-rank-row ${i === 0 && r.score > 0 ? "top" : ""}`}>
                  <span className="jt-muted">{i + 1}.</span>
                  <button className="jt-btn ghost id" style={{ padding: "0.1rem 0.3rem", textAlign: "left" }} onClick={() => setFocus(r.hole)}>{r.hole}</button>
                  <span className="bar" aria-hidden="true"><i style={{ width: `${r.score * 100}%` }} /></span>
                  <span className="score">{r.score.toFixed(2)}</span>
                </div>
              ))}
            </div>
          )}
          <p className="jt-small jt-muted" style={{ marginTop: "0.9rem" }}>
            score = failing dependents / √(all failing × all dependents). Ties keep teaching order.
            The spectrum is this measured map, not line coverage.
          </p>
        </section>

        {focused && (
          <section className="jt-panel jt-pad">
            <div className="jt-chips" style={{ marginBottom: "0.5rem" }}>
              <span className="jt-chip kc">{focused.kc}</span>
              <span className="jt-chip">stage {focused.stage}</span>
              <span className="jt-chip info">inferred: {project.baseline.inferred[focused.id] ?? "?"}</span>
            </div>
            <h3><code>{focused.id}</code></h3>
            <p className="jt-muted jt-small">{focused.summary}</p>
            <Spec text={focused.spec} />
          </section>
        )}
      </div>
    </div>
  );
}
