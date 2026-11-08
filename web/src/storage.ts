// Per-browser learner state (localStorage). Mirrors the shape of
// .tutor/state.toml from the CLI, but lives only in this browser: it can be
// absent (private window, blocked storage), so every access is guarded and the
// site works without it.
import { useEffect, useState } from "react";
import type { SM2State } from "./models";

export interface ItemState extends SM2State {
  due: string;
}

export interface WebState {
  kc: Record<string, number>;
  items: Record<string, ItemState>;
  misconceptions: Record<string, number>;
}

const KEY = "julia-tutor/state/v1";
const empty = (): WebState => ({ kc: {}, items: {}, misconceptions: {} });

export function loadState(): WebState {
  try {
    const raw = window.localStorage.getItem(KEY);
    if (!raw) return empty();
    const s = JSON.parse(raw) as Partial<WebState>;
    return { kc: s.kc ?? {}, items: s.items ?? {}, misconceptions: s.misconceptions ?? {} };
  } catch {
    return empty();
  }
}

export function saveState(s: WebState): void {
  try {
    window.localStorage.setItem(KEY, JSON.stringify(s));
  } catch {
    /* storage unavailable: progress lasts for this page view only */
  }
}

/** React hook: state plus a setter that persists. */
export function useWebState(): [WebState, (f: (s: WebState) => WebState) => void, () => void] {
  const [state, setState] = useState<WebState>(empty);
  useEffect(() => setState(loadState()), []);
  const update = (f: (s: WebState) => WebState) =>
    setState((prev) => {
      const next = f(prev);
      saveState(next);
      return next;
    });
  const reset = () => update(() => empty());
  return [state, update, reset];
}

export const todayISO = (): string => {
  const d = new Date();
  const z = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${z(d.getMonth() + 1)}-${z(d.getDate())}`;
};
