import { Report } from "../components/Report";
import { course, estimateText, landingHref, statusNote, type CourseInfo } from "../course";
import { data } from "../data";
import { guided } from "../guided";

// The homepage: the courses first, the two flagship courses as the
// destination and Core Julia as the way in; then what exists so far, as counts
// of what was built (not of what anyone learned); then how the feedback works.
const ROLE: Record<string, string> = {
  core: "The way in",
  science: "The packages in between",
  scicomp: "Destination",
  sciml: "Destination",
};

export function HeroView() {
  const p = data.projects[0];
  const checks = data.lessons.reduce((n, l) => n + l.checks.length, 0);
  const mutants = Object.values(p.mutants).flat();
  const featured = p.fixtures.find((f) => f.name === "pvar_binding-mutates-bindings") ?? p.fixtures[0];
  const head = featured.golden.split("\n").slice(0, 12).join("\n");
  const byId = (id: string) => course.courses.find((c) => c.id === id);
  const [core, science] = [byId("core"), byId("science")];
  const flagships = course.courses.filter((c) => ROLE[c.id] === "Destination");
  const readyUnits = course.units.filter((u) => u.status === "ready").length;
  const problems = course.units.reduce((n, u) => n + u.problems.length, 0);
  const guidedReady = guided.projects.filter((g) => g.status === "ready").length;

  return (
    <div className="jt-grid" style={{ gap: "1.5rem" }}>
      <section className="jt-hero">
        <div className="jt-eyebrow"><span className="jt-pips" aria-hidden="true"><i /><i /><i /></span>&nbsp; Julia {data.julia} · rule-based, no LLM in the feedback</div>
        <h2 style={{ marginTop: "0.6rem", maxWidth: "48rem" }}>Scientific computing and scientific ML in Julia, with feedback you can <em>trace back</em>.</h2>
        <p className="lede" style={{ maxWidth: "48rem" }}>
          Four courses. Scientific computing and Scientific ML are where they lead; Core Julia is the way in, and
          Julia for science covers the packages in between. Every example output on this site was recorded by running
          it. Practice problems are graded on your own machine, in a sandbox, for correctness first and then for
          speed, memory and type stability relative to a reference solution.
        </p>
      </section>

      <section aria-label="Courses" className="jt-paths">
        <div className="jt-paths-row">
          {core && <CourseCard c={core} />}
          <span className="jt-paths-arrow" aria-hidden="true">→</span>
          {science && <CourseCard c={science} />}
          <span className="jt-paths-arrow" aria-hidden="true">→</span>
          <div className="jt-paths-dest">
            {flagships.map((c) => <CourseCard key={c.id} c={c} />)}
          </div>
        </div>
      </section>

      <section className="jt-panel jt-pad" aria-labelledby="built-heading">
        <div className="jt-eyebrow" id="built-heading">What exists so far: counts of what was built, not of what learners learned</div>
        <div className="jt-stats">
          <div className="jt-stat"><b>{readyUnits}</b><span>units with recorded outputs</span></div>
          <div className="jt-stat"><b>{problems}</b><span>practice problems with tested graders</span></div>
          <div className="jt-stat"><b>{guidedReady}</b><span>guided projects with hidden tests</span></div>
          <div className="jt-stat"><b>{checks}</b><span>quiz checks, keys verified by running</span></div>
          <div className="jt-stat"><b>{data.rules.length}</b><span>checker rules with hint ladders</span></div>
          <div className="jt-stat"><b>{mutants.filter((m) => m.caught).length}/{mutants.length}</b><span>wrong symdiff bodies caught by its tests</span></div>
        </div>
        <p className="jt-small jt-muted" style={{ margin: "0.8rem 0 0" }}>
          Learner outcomes: none measured yet. No learner has taken a course; a pilot will measure how long the
          courses take and what learners can do afterwards, and its numbers will appear here.
        </p>
      </section>

      <section className="jt-hero-grid jt-panel jt-pad" aria-label="How the feedback works">
        <div>
          <div className="jt-eyebrow">How the feedback works (the symdiff project)</div>
          <ol className="jt-howlist">
            <li><b>Fill a hole.</b> A starter package has functions with TODO bodies; the docstring is the specification.</li>
            <li><b>Run the tests.</b> Behavioural tests, exact where possible, tolerances derived where not, in a fresh process.</li>
            <li><b>Explain.</b> Failures, checker findings and measurements are joined through the measured test-to-hole map.</li>
            <li><b>Learn.</b> Short lessons target the misconception behind the bug, and <code>tutor progress</code> schedules reviews of them with SM-2.</li>
          </ol>
          <div className="jt-chips">
            <a className="jt-btn" href="explain.html" style={{ textDecoration: "none" }}>See explain at work</a>
            <a className="jt-btn ghost" href="design.html" style={{ textDecoration: "none" }}>Why it is built this way</a>
          </div>
        </div>
        <Report text={head} title={`explain · ${featured.name}`} wrap />
      </section>
    </div>
  );
}

function CourseCard({ c }: { c: CourseInfo }) {
  const note = statusNote(c);
  return (
    <a className="jt-panel jt-pad jt-coursecard" href={landingHref(c.id)}>
      <span className="jt-eyebrow">{ROLE[c.id] ?? `Course ${c.order}`}{note && <> · <span className="jt-chip advice">{note}</span></>}</span>
      <h3>{c.title}</h3>
      <span className="jt-small">{c.summary}</span>
      <span className="jt-small jt-muted">{c.units.length} units · {c.problems} problems · {estimateText(c)}</span>
    </a>
  );
}
