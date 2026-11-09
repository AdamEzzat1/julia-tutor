import type { ReactNode } from "react";
import { Code } from "./Code";

// Markdown for course prose: paragraphs, fenced code blocks, bullet and
// numbered lists, `code`, **strong**, *em* and [links](https://...). Text is
// authored in this repo and rendered as React nodes, never as HTML.

export type Block =
  | { kind: "p"; text: string }
  | { kind: "code"; text: string }
  | { kind: "ul" | "ol"; items: string[] };

export function parseBlocks(src: string): Block[] {
  const lines = src.replace(/\r\n/g, "\n").split("\n");
  const out: Block[] = [];
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    if (/^\s*```/.test(line)) {
      const body: string[] = [];
      i++;
      while (i < lines.length && !/^\s*```/.test(lines[i])) body.push(lines[i++]);
      i++; // closing fence
      out.push({ kind: "code", text: body.join("\n") });
    } else if (/^\s*([*-]|\d+\.)\s+/.test(line)) {
      const ordered = /^\s*\d+\./.test(line);
      const items: string[] = [];
      while (i < lines.length && lines[i].trim() !== "" && !/^\s*```/.test(lines[i])) {
        const m = /^\s*(?:[*-]|\d+\.)\s+(.*)$/.exec(lines[i]);
        if (m) items.push(m[1]);
        else if (items.length) items[items.length - 1] += " " + lines[i].trim();
        i++;
      }
      out.push({ kind: ordered ? "ol" : "ul", items });
    } else if (line.trim() === "") {
      i++;
    } else {
      const para: string[] = [];
      while (i < lines.length && lines[i].trim() !== "" && !/^\s*```/.test(lines[i]) && !/^\s*([*-]|\d+\.)\s+/.test(lines[i]))
        para.push(lines[i++].trim());
      out.push({ kind: "p", text: para.join(" ") });
    }
  }
  return out;
}

export function md(text: string): ReactNode[] {
  const out: ReactNode[] = [];
  const re = /(`[^`]+`)|(\*\*[^*]+\*\*)|(\*[^*\s][^*]*\*)|(\[[^\]]+\]\((https?:\/\/[^)\s]+)\))/g;
  let last = 0;
  let k = 0;
  for (const m of text.matchAll(re)) {
    const i = m.index ?? 0;
    if (i > last) out.push(text.slice(last, i));
    const t = m[0];
    if (m[1]) out.push(<code key={k++}>{t.slice(1, -1)}</code>);
    else if (m[2]) out.push(<strong key={k++}>{md(t.slice(2, -2))}</strong>);
    else if (m[3]) out.push(<em key={k++}>{t.slice(1, -1)}</em>);
    else if (m[4]) {
      const label = t.slice(1, t.indexOf("]("));
      out.push(<a key={k++} href={m[5]} target="_blank" rel="noreferrer">{label}</a>);
    }
    last = i + t.length;
  }
  if (last < text.length) out.push(text.slice(last));
  return out;
}

export function Markdown({ text }: { text: string }) {
  return (
    <div className="jt-md">
      {parseBlocks(text).map((b, i) =>
        b.kind === "code" ? <Code key={i} src={b.text} /> :
        b.kind === "p" ? <p key={i}>{md(b.text)}</p> :
        b.kind === "ul" ? <ul key={i}>{b.items.map((it, j) => <li key={j}>{md(it)}</li>)}</ul> :
        <ol key={i}>{b.items.map((it, j) => <li key={j}>{md(it)}</li>)}</ol>,
      )}
    </div>
  );
}
