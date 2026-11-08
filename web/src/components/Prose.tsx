import type { ReactNode } from "react";

// Minimal Markdown for lesson bodies, hints and specs: paragraphs, `code`,
// *em* and **strong**. Lesson text is authored in this repo, never user input,
// and is rendered as React nodes (no innerHTML).
export function inline(text: string): ReactNode[] {
  const out: ReactNode[] = [];
  const re = /(`[^`]+`)|(\*\*[^*]+\*\*)|(\*[^*\s][^*]*\*)/g;
  let last = 0;
  let k = 0;
  for (const m of text.matchAll(re)) {
    const i = m.index ?? 0;
    if (i > last) out.push(text.slice(last, i));
    const t = m[0];
    if (t.startsWith("`")) out.push(<code key={k++}>{t.slice(1, -1)}</code>);
    else if (t.startsWith("**")) out.push(<strong key={k++}>{t.slice(2, -2)}</strong>);
    else out.push(<em key={k++}>{t.slice(1, -1)}</em>);
    last = i + t.length;
  }
  if (last < text.length) out.push(text.slice(last));
  return out;
}

export function Prose({ text }: { text: string }) {
  const paras = text.trim().split(/\n\s*\n/);
  return (
    <>
      {paras.map((p, i) => (
        <p key={i}>{inline(p.replace(/\s*\n\s*/g, " "))}</p>
      ))}
    </>
  );
}

/** A docstring spec: the signature block (indented) as code, the rest as prose. */
export function Spec({ text }: { text: string }) {
  const lines = text.split("\n");
  const sig: string[] = [];
  let i = 0;
  while (i < lines.length && /^ {4}/.test(lines[i])) sig.push(lines[i++].slice(4));
  return (
    <div>
      {sig.length > 0 && <pre className="jt-code">{sig.join("\n")}</pre>}
      <Prose text={lines.slice(i).join("\n")} />
    </div>
  );
}
