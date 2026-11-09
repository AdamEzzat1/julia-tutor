import { useRef, type KeyboardEvent } from "react";
import { highlight } from "./Code";

// A code editor without a dependency: a transparent <textarea> over a
// highlighted <pre> with identical metrics. Tab indents by four spaces,
// Shift+Tab outdents, Ctrl/Cmd+Enter runs.

const INDENT = "    ";

export function Editor({ value, onChange, onRun, label, minRows = 8 }: {
  value: string;
  onChange: (v: string) => void;
  onRun?: () => void;
  label: string;
  minRows?: number;
}) {
  const ta = useRef<HTMLTextAreaElement>(null);
  const pre = useRef<HTMLPreElement>(null);
  const rows = Math.max(minRows, value.split("\n").length + 1);

  const edit = (next: string, start: number, end: number) => {
    onChange(next);
    requestAnimationFrame(() => ta.current?.setSelectionRange(start, end));
  };

  const onKey = (e: KeyboardEvent<HTMLTextAreaElement>) => {
    const el = e.currentTarget;
    const { selectionStart: s, selectionEnd: t } = el;
    if ((e.ctrlKey || e.metaKey) && e.key === "Enter") {
      e.preventDefault();
      onRun?.();
      return;
    }
    if (e.key !== "Tab") return;
    e.preventDefault();
    const lineStart = value.lastIndexOf("\n", s - 1) + 1;
    if (!e.shiftKey && s === t) {
      edit(value.slice(0, s) + INDENT + value.slice(t), s + INDENT.length, s + INDENT.length);
      return;
    }
    // Indent or outdent every selected line.
    const block = value.slice(lineStart, t);
    const lines = block.split("\n");
    const changed = e.shiftKey ? lines.map((l) => l.replace(/^ {1,4}/, "")) : lines.map((l) => INDENT + l);
    const next = changed.join("\n");
    const firstDelta = changed[0].length - lines[0].length;
    edit(value.slice(0, lineStart) + next + value.slice(t), Math.max(lineStart, s + firstDelta), t + next.length - block.length);
  };

  return (
    <div className="jt-editor">
      <pre ref={pre} className="jt-code jt-editor-hl" aria-hidden="true">
        {highlight(value)}
        {"\n"}
      </pre>
      <textarea
        ref={ta}
        aria-label={label}
        value={value}
        rows={rows}
        spellCheck={false}
        autoCapitalize="off"
        autoComplete="off"
        autoCorrect="off"
        onChange={(e) => onChange(e.target.value)}
        onKeyDown={onKey}
        onScroll={(e) => {
          if (pre.current) {
            pre.current.scrollTop = e.currentTarget.scrollTop;
            pre.current.scrollLeft = e.currentTarget.scrollLeft;
          }
        }}
      />
    </div>
  );
}
