// Renders a `tutor explain` report (a golden output) as an instrument printout.
// The text is shown verbatim; only each line's colour rail is inferred from its
// shape, so nothing is reworded between the CLI and the site.

export function classify(line: string): string {
  const t = line.trimStart();
  if (t.startsWith("== tutor explain")) return "title";
  if (t.startsWith("Start here:")) return "start";
  if (/^(why:|It still has|Tests raised|finding inside|Read its docstring|Nothing else can be checked)/.test(t)) return "why";
  if (t.startsWith("measured:")) return "measured";
  if (/^(Tests:|Holes at stage|Static findings|Measurements \(|All \d+ testsets pass)/.test(t)) return "section";
  if (t.startsWith("FAIL ")) return "fail";
  if (/^test\/\S+:\d+ (FAIL|ERROR)/.test(t)) return "failmsg";
  if (/ADVICE/.test(t)) return "advice";
  if (/ WARN /.test(t)) return "warn";
  return "";
}

export function Report({ text, title, wrap = false }: { text: string; title: string; wrap?: boolean }) {
  const lines = text.replace(/\n$/, "").split("\n");
  return (
    <figure className={`jt-report${wrap ? " wrap" : ""}`} style={{ margin: 0 }}>
      <figcaption className="jt-report-head">
        <span>
          <span className="jt-pips" aria-hidden="true"><i /><i /><i /></span>
          &nbsp;&nbsp;{title}
        </span>
        <span>golden output · verbatim</span>
      </figcaption>
      <div className="jt-report-body" role="region" aria-label={`${title} report`} tabIndex={0}>
        {lines.map((l, i) => (
          <span key={i} className={`jt-line ${classify(l)}`}>{l || " "}</span>
        ))}
      </div>
    </figure>
  );
}
