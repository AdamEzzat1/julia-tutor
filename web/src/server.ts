// Connection to `tutor serve`, the learner's own Julia on 127.0.0.1.
//
// `tutor serve` prints a link ending in #connect=<port>.<token>. The fragment
// never leaves the browser (fragments are not sent in requests); we read it,
// keep it in localStorage, and remove it from the address bar. Every request
// carries the token as a Bearer header, which the server requires, and which
// also makes the browser preflight each request so the server can check the
// page's origin.
import { useSyncExternalStore } from "react";
import type { Ladder } from "./ladder";

export interface Connection {
  port: number;
  token: string;
}

export type Status =
  | { kind: "none" }
  | { kind: "checking" }
  | { kind: "connected"; julia: string; envs: string[]; sandbox: "docker" | "none" }
  | { kind: "offline"; message: string }
  | { kind: "unauthorized" };

const KEY = "julia-tutor/server/v1";

/** Parse "#connect=8749.<48 hex chars>" (other fragment content is ignored). */
export function parseConnect(hash: string): Connection | null {
  const m = /(?:^#|&)connect=(\d{2,5})\.([0-9a-f]{48})(?:&|$)/.exec(hash);
  if (!m) return null;
  const port = Number(m[1]);
  if (port < 1024 || port > 65535) return null;
  return { port, token: m[2] };
}

export function loadConnection(): Connection | null {
  try {
    const raw = window.localStorage.getItem(KEY);
    if (!raw) return null;
    const c = JSON.parse(raw) as Partial<Connection>;
    return typeof c.port === "number" && typeof c.token === "string" ? { port: c.port, token: c.token } : null;
  } catch {
    return null;
  }
}

function saveConnection(c: Connection | null) {
  try {
    if (c) window.localStorage.setItem(KEY, JSON.stringify(c));
    else window.localStorage.removeItem(KEY);
  } catch {
    /* storage unavailable: the connection lasts for this page view */
  }
}

// ---- a tiny shared store, so every view on the page sees one connection ----

let conn: Connection | null = null;
let status: Status = { kind: "none" };
const listeners = new Set<() => void>();
const emit = () => listeners.forEach((l) => l());
let snapshot: { conn: Connection | null; status: Status } = { conn, status };

function set(c: Connection | null, s: Status) {
  conn = c;
  status = s;
  snapshot = { conn, status };
  emit();
}

export function useServer() {
  return useSyncExternalStore(
    (l) => {
      listeners.add(l);
      return () => listeners.delete(l);
    },
    () => snapshot,
    () => snapshot,
  );
}

const base = (c: Connection) => `http://127.0.0.1:${c.port}`;

async function call<T>(path: string, body?: unknown, signal?: AbortSignal): Promise<T> {
  if (!conn) throw new Error("not connected");
  const res = await fetch(base(conn) + path, {
    method: body === undefined ? "GET" : "POST",
    headers: { Authorization: `Bearer ${conn.token}`, ...(body === undefined ? {} : { "Content-Type": "application/json" }) },
    body: body === undefined ? undefined : JSON.stringify(body),
    signal,
  });
  if (res.status === 401) {
    set(conn, { kind: "unauthorized" });
    throw new Error("The server rejected the token: open the link `tutor serve` printed.");
  }
  const data = (await res.json()) as T & { error?: string };
  if (!res.ok) throw new Error(data.error ?? `HTTP ${res.status}`);
  return data;
}

export async function checkHealth(): Promise<void> {
  if (!conn) return set(null, { kind: "none" });
  set(conn, { kind: "checking" });
  try {
    const h = await call<{ julia: string; envs: string[]; sandbox?: string }>("/api/health");
    // servers older than the container sandbox send no `sandbox`: they run plain processes
    set(conn, { kind: "connected", julia: h.julia, envs: h.envs, sandbox: h.sandbox === "docker" ? "docker" : "none" });
  } catch (e) {
    if (status.kind === "unauthorized") return;
    set(conn, {
      kind: "offline",
      message: e instanceof TypeError ? "No server answered on this port. Is `tutor serve` running?" : String((e as Error).message),
    });
  }
}

/** Called once per page: adopt a #connect fragment, else the stored connection. */
let started = false;
export function initServer(): void {
  if (started || typeof window === "undefined") return;
  started = true;
  const fromHash = parseConnect(window.location.hash);
  if (fromHash) {
    saveConnection(fromHash);
    history.replaceState(null, "", window.location.pathname + window.location.search);
  }
  const c = fromHash ?? loadConnection();
  set(c, c ? { kind: "checking" } : { kind: "none" });
  void checkHealth();
}

export function connectManually(port: number, token: string): boolean {
  const c = parseConnect(`#connect=${port}.${token.trim()}`);
  if (!c) return false;
  saveConnection(c);
  set(c, { kind: "checking" });
  void checkHealth();
  return true;
}

export function disconnect(): void {
  saveConnection(null);
  set(null, { kind: "none" });
}

// ---- endpoints -----------------------------------------------------------------

export interface RunImage {
  name: string;
  mime: "image/png" | "image/svg+xml";
  data: string; // base64
}

export interface RunResult {
  output: string;
  ok: boolean;
  timed_out: boolean;
  seconds: number;
  images?: RunImage[]; // absent from servers older than figure support
}

export interface FeedbackItem {
  level: "pass" | "warn" | "fail" | "info";
  title: string;
  detail: string;
}

export interface Failure {
  case: number;
  input: string;
  reason: string;
  expected: string;
  got: string;
  shown: boolean;
}

export interface GradeResult {
  problem: string;
  status: "passed" | "failed" | "load-error" | "no-entry" | "timeout" | "crash" | "internal-error";
  correctness: { passed: number; total: number; explicit: number; failures: Failure[] } | null;
  performance: {
    overall: "excellent" | "good" | "needs-work";
    timed_out: boolean;
    /** measurement failed (an error at the perf sizes); the feedback item has the message */
    error?: string;
    time?: "fast" | "par" | "slower" | "slow";
    ratio?: number;
    memory?: "ok" | "allocates";
    growth?: "ok" | "worse";
    types?: "stable" | "unstable";
    sizes?: { n: number; sub_ns: number; ref_ns: number; sub_bytes: number; ref_bytes: number }[];
  } | null;
  feedback: FeedbackItem[];
  findings: { rule: string; severity: string; line: number; message: string }[];
  verdicts: string[];
  /** the performance ladder (Practice.ladder); absent from an older tutor serve */
  ladder?: Ladder;
  seconds: number;
}

export const runCode = (code: string, env: string, signal?: AbortSignal) =>
  call<RunResult>("/api/run", { code, env, mode: "repl" }, signal);

export const gradeCode = (problem: string, code: string, signal?: AbortSignal) =>
  call<GradeResult>("/api/grade", { problem, code }, signal);
