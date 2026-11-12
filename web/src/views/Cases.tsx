import { course, landingHref, statusNote } from "../course";

/**
 * The cases index: what a case project is, and the cases each course plans,
 * read from the course manifests' outcomes ("planned"). None is built yet, and
 * the page says so; a built case will get its own page.
 */
export function CasesView() {
  const byCourse = course.courses
    .map((c) => ({ c, planned: [...new Set(c.outcomes.flatMap((o) => o.planned))] }))
    .filter((g) => g.planned.length > 0);

  return (
    <div className="jt-grid" style={{ gap: "1.1rem" }}>
      <section className="jt-panel jt-pad">
        <div className="jt-eyebrow">Status</div>
        <h3 style={{ marginTop: "0.25rem" }}>No case project is ready yet</h3>
        <p style={{ maxWidth: "48rem" }}>
          The first to be built is the odeint case (milestone M4): write an ODE integrator (Dormand–Prince 5(4)) and
          use it on orbital mechanics. Everything below is planned (cases, capstones and the full programs that end
          each course): listed because a course outcome is waiting for it, not because it exists.
        </p>
      </section>

      <section className="jt-panel jt-pad">
        <div className="jt-eyebrow">What a case is</div>
        <p style={{ maxWidth: "48rem" }}>
          A case starts from a scientific question and a quantity of interest with a required accuracy. You work
          through the same eight steps each time, with less scaffolding in later cases: state the question; estimate
          the answer from scales before any code runs; write down the model and its assumptions; choose a method and
          justify it; verify the code; validate the model; quantify uncertainty; report only what the evidence
          supports.
        </p>
        <p style={{ maxWidth: "48rem", marginBottom: 0 }}>
          As designed, software will check part of it: hidden acceptance tests, mutants, and a claim checker that
          every number in your report equals what your own code computes. <strong>No software will grade the
          reasoning.</strong> That part is assessed with a published rubric, by yourself, a peer or an instructor.
        </p>
      </section>

      {byCourse.map(({ c, planned }) => (
        <section key={c.id} className="jt-panel jt-pad">
          <div className="jt-eyebrow">
            <a href={landingHref(c.id)}>{c.title}</a>{statusNote(c) && <> · <span className="jt-chip advice">{statusNote(c)}</span></>}
          </div>
          <ul style={{ margin: "0.4rem 0 0" }}>
            {planned.map((p) => <li key={p}>{p} <span className="jt-chip">planned</span></li>)}
          </ul>
        </section>
      ))}
    </div>
  );
}
