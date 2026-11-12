import { md } from "../components/Markdown";
import {
  course, courseById, crossPrerequisites, estimateText, landingHref, statusNote, unitHref, unitNumber, type CourseInfo,
} from "../course";
import type { MountProps } from "../main";

const REPO = "https://github.com/AdamEzzat1/julia-tutor";

/** A course's landing page (site/course-<id>.qmd): outcomes, estimate, prerequisites, setup, units. */
export function CourseLandingView({ mount }: MountProps) {
  const c = courseById(mount.course ?? "");
  if (!c) return <p>Unknown course: {mount.course}</p>;
  const units = course.units.filter((u) => u.course === c.id);
  const ready = units.filter((u) => u.status === "ready");
  const first = ready[0];
  const note = statusNote(c);

  return (
    <div className="jt-grid" style={{ gap: "1.1rem" }}>
      <section className="jt-panel jt-pad">
        <div className="jt-eyebrow">
          Course {c.order} of {course.courses.length}
          {note && <> · <span className="jt-chip advice">{note}</span></>}
        </div>
        <p className="lede" style={{ maxWidth: "48rem", marginTop: "0.5rem" }}>{c.summary}</p>
        {note && (
          <div className="jt-callout mis" style={{ marginTop: "0.6rem" }}>
            <span className="tag">{note}</span>
            <div>
              This course is not finished. {c.status_note} {ready.length} of its {units.length} units are ready; the
              cases and program that will assess some of its outcomes are not built yet (listed under each outcome
              below).
            </div>
          </div>
        )}
        <div className="jt-chips" style={{ marginTop: "0.8rem" }}>
          {first && <a className="jt-btn primary" href={unitHref(first.id)} style={{ textDecoration: "none" }}>Start with unit {unitNumber(first.id)}</a>}
          <a className="jt-btn" href={`course.html?course=${c.id}`} style={{ textDecoration: "none" }}>All units of this course</a>
        </div>
      </section>

      <div className="jt-landing-facts">
        <section className="jt-panel jt-pad">
          <div className="jt-eyebrow">Time</div>
          <h4 style={{ margin: "0.3rem 0" }}>{estimateText(c)}</h4>
          <p className="jt-small jt-muted" style={{ margin: 0 }}>
            Not measured: nobody has taken this course yet. Computed from {c.estimate.basis}. A pilot with real
            learners will replace it.
          </p>
        </section>
        <section className="jt-panel jt-pad">
          <div className="jt-eyebrow">Before this course</div>
          <Prerequisites c={c} />
        </section>
        <section className="jt-panel jt-pad">
          <div className="jt-eyebrow">Setup</div>
          <Setup c={c} />
        </section>
      </div>

      <section className="jt-panel jt-pad">
        <div className="jt-eyebrow">Outcomes</div>
        <h3 style={{ marginTop: "0.25rem" }}>After this course you can</h3>
        <ol className="jt-outcomes">
          {c.outcomes.map((o, i) => (
            <li key={i}>
              <div>{md(o.text)}</div>
              <div className="jt-chips" style={{ marginTop: "0.35rem" }}>
                {o.assessed_by.map((a) => <AssessedBy key={a} a={a} />)}
                {o.planned.map((p) => <span key={p} className="jt-chip" title="Not built yet">planned: {p}</span>)}
              </div>
            </li>
          ))}
        </ol>
        <p className="jt-small jt-muted">
          Each outcome lists the units and projects whose problems and checks assess it. That a unit assesses an
          outcome is the authors' mapping; whether learners reach the outcome has not been measured.
        </p>
      </section>

      <section className="jt-panel jt-pad">
        <div className="jt-eyebrow">Units</div>
        <h3 style={{ marginTop: "0.25rem" }}>{units.length} units · {c.problems} practice problems</h3>
        <ol className="jt-unitlist">
          {units.map((u) => (
            <li key={u.id}>
              <a className="jt-linkbtn" href={unitHref(u.id)}>
                <span className="num">{unitNumber(u.id)}</span>
                <span className="title">{u.title.split(/:\s/)[0]}</span>
                <span className="meta">{u.status === "planned" ? "planned" : u.problems.length ? `${u.problems.length} problems` : ""}</span>
              </a>
            </li>
          ))}
        </ol>
        {(c.projects.length > 0 || c.guided.length > 0) && (
          <p className="jt-small" style={{ marginBottom: 0 }}>
            Projects:{" "}
            {c.projects.map((p) => <a key={p} className="jt-chip" href="explain.html">{p} (fill the holes)</a>)}
            {c.guided.map((g) => <a key={g} className="jt-chip" href={`projects.html?project=${g}`}>{g}</a>)}
          </p>
        )}
      </section>
    </div>
  );
}

function AssessedBy({ a }: { a: string }) {
  if (a.startsWith("project:")) return <a className="jt-chip kc" href="explain.html">project {a.slice(8)}</a>;
  if (a.startsWith("guided:")) return <a className="jt-chip kc" href={`projects.html?project=${a.slice(7)}`}>project {a.slice(7)}</a>;
  return <a className="jt-chip kc" href={unitHref(a)}>unit {unitNumber(a)}</a>;
}

function Prerequisites({ c }: { c: CourseInfo }) {
  const cross = crossPrerequisites(c);
  if (c.requires.length === 0 && cross.length === 0)
    return <p style={{ margin: "0.3rem 0 0" }}>Nothing: this is the way in. You need Docker and git (see Setup).</p>;
  return (
    <ul className="jt-small" style={{ margin: "0.3rem 0 0", paddingLeft: "1.1rem" }}>
      {c.requires.map((r) => {
        const rc = courseById(r);
        return <li key={r}>the whole of <a href={landingHref(r)}>{rc?.title ?? r}</a>{rc && statusNote(rc) ? ` (${statusNote(rc)})` : ""}</li>;
      })}
      {cross.map((g) => (
        <li key={g.course.id}>
          units of <a href={landingHref(g.course.id)}>{g.course.title}</a> that its units build on directly:{" "}
          {g.units.map((u, i) => <span key={u}>{i > 0 && ", "}<a href={unitHref(u)}>unit {unitNumber(u)}</a></span>)}
        </li>
      ))}
    </ul>
  );
}

function Setup({ c }: { c: CourseInfo }) {
  return (
    <div className="jt-small">
      <p style={{ margin: "0.3rem 0" }}>
        Every Run happens on your machine, in a sandbox container with no network and no access to your files. With
        Docker running, in a clone of the repository:
      </p>
      <pre className="jt-code" aria-label="Shell commands"><code style={{ all: "unset" }}>{`./tutor sandbox pull ${c.id}\n./tutor serve --course=${c.id}`}</code></pre>
      <p className="jt-muted" style={{ margin: "0.3rem 0" }}>On Windows, <code>.\tutor.ps1</code> instead of <code>./tutor</code>.</p>
      <p style={{ margin: "0.3rem 0 0" }}>Download: {c.setup.download}.</p>
      <p className="jt-muted" style={{ margin: "0 0 0.3rem" }}>Measured: {c.setup.measured}.</p>
      <p style={{ margin: "0.3rem 0 0" }}>
        {c.id === "core"
          ? <>From nothing, step by step: <a href={`${REPO}/blob/main/docs/START_CORE.md`}>Start Core Julia in 10 minutes</a> (timed on a fresh CI machine).</>
          : <>First time? Follow <a href={`${REPO}/blob/main/docs/START_CORE.md`}>Start Core Julia</a>, then pull this course&apos;s image.</>}
      </p>
    </div>
  );
}
