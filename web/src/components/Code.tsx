import { Fragment, type ReactNode } from "react";

// A small Julia highlighter: enough for lesson snippets and specs, no
// dependency. Token classes match .jt-code in styles.css.
const KEYWORDS = new Set([
  "function", "end", "if", "elseif", "else", "for", "while", "return", "struct", "mutable",
  "abstract", "type", "where", "begin", "let", "do", "try", "catch", "finally", "module",
  "using", "import", "export", "const", "local", "global", "in", "isa", "true", "false",
  "nothing", "missing", "macro", "quote", "break", "continue",
]);

const TOKEN = new RegExp(
  [
    String.raw`(?<c>#.*)`,
    String.raw`(?<s>"""[\s\S]*?"""|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])')`,
    String.raw`(?<m>@[A-Za-z_][\w!]*)`,
    String.raw`(?<t>(?<=::)\s*[A-Z][\w.]*(?:\{[^}]*\})?)`,
    String.raw`(?<n>\b\d[\d_]*(?:\.\d+)?(?:e[+-]?\d+)?(?:\/\/\d+)?\b)`,
    String.raw`(?<w>[A-Za-z_][\w!]*)(?<call>\()?`,
  ].join("|"),
  "g",
);

export function highlight(src: string): ReactNode[] {
  const out: ReactNode[] = [];
  let last = 0;
  let key = 0;
  for (const m of src.matchAll(TOKEN)) {
    const i = m.index ?? 0;
    if (i > last) out.push(src.slice(last, i));
    const g = m.groups ?? {};
    if (g.c) out.push(<span key={key++} className="c">{g.c}</span>);
    else if (g.s) out.push(<span key={key++} className="s">{g.s}</span>);
    else if (g.m) out.push(<span key={key++} className="m">{g.m}</span>);
    else if (g.t) out.push(<span key={key++} className="t">{g.t}</span>);
    else if (g.n) out.push(<span key={key++} className="n">{g.n}</span>);
    else if (g.w) {
      if (KEYWORDS.has(g.w)) out.push(<span key={key++} className="k">{g.w}</span>);
      else if (g.call) out.push(<span key={key++} className="f">{g.w}</span>);
      else out.push(<Fragment key={key++}>{g.w}</Fragment>);
      if (g.call) out.push("(");
    }
    last = i + m[0].length;
  }
  if (last < src.length) out.push(src.slice(last));
  return out;
}

export function Code({ src, label }: { src: string; label?: string }) {
  return (
    <pre className="jt-code" aria-label={label ?? "Julia code"}>
      <code style={{ all: "unset" }}>{highlight(src.replace(/\n$/, ""))}</code>
    </pre>
  );
}
