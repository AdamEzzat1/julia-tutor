import { useEffect, useRef, useState } from "react";
import { course } from "../course";
import {
  checkHealth, connectManually, disconnect, initServer, runCode, useServer, type RunResult,
} from "../server";
import { Editor } from "./Editor";

/** Status pill shown wherever code can run. */
export function ServerPill() {
  const { status } = useServer();
  useEffect(initServer, []);
  const label =
    status.kind === "connected" ? `Julia ${status.julia} · ${status.sandbox === "docker" ? "sandboxed" : "not sandboxed"}` :
    status.kind === "checking" ? "connecting…" :
    status.kind === "offline" ? "Julia not reachable" :
    status.kind === "unauthorized" ? "token rejected" : "not connected";
  const cls = status.kind === "connected" ? (status.sandbox === "docker" ? "pass" : "advice") :
    status.kind === "checking" ? "info" : "fail";
  return (
    <a className={`jt-chip ${cls} jt-pill`} href="sandbox.html#setup" title="Code runs in your own Julia via `tutor serve`">
      <i aria-hidden="true" />{label}
    </a>
  );
}

/** How to start the local server; shown until a connection works. */
export function ConnectPanel({ compact = false }: { compact?: boolean }) {
  const { status, conn } = useServer();
  useEffect(initServer, []);
  const [port, setPort] = useState("8749");
  const [token, setToken] = useState("");
  const [bad, setBad] = useState(false);
  if (status.kind === "connected") {
    return compact ? null : (
      <div className={`jt-callout ${status.sandbox === "docker" ? "ok" : "mis"}`} style={{ margin: 0 }}>
        <span className="tag">Connected</span>
        <div>
          {status.sandbox === "docker"
            ? <>Code runs in Julia {status.julia} through 127.0.0.1:{conn?.port}, each run in a fresh container with no
                network and no access to your files.</>
            : <>Code runs in your Julia {status.julia} on 127.0.0.1:{conn?.port} as plain processes with your account's
                access to files and the network (the server was started with <code>--sandbox=none</code>).</>}
          Environments: {status.envs.join(", ")}.{" "}
          <button className="jt-btn ghost jt-small" onClick={disconnect}>Forget this connection</button>
        </div>
      </div>
    );
  }
  return (
    <section className="jt-panel jt-pad jt-connect" id="setup" aria-labelledby="jt-connect-h">
      <div className="jt-eyebrow">Run code in your own Julia</div>
      <h3 id="jt-connect-h" style={{ marginTop: "0.25rem" }}>
        {status.kind === "offline" ? "Your Julia server isn't answering" :
         status.kind === "unauthorized" ? "The server rejected this page's token" :
         status.kind === "checking" ? "Connecting…" : "Connect the site to Julia on your machine"}
      </h3>
      {status.kind === "offline" && <p className="jt-small jt-muted">{status.message}</p>}
      <ol className="jt-steps">
        <li>Install Julia 1.10 with <a href="https://julialang.org/downloads/" target="_blank" rel="noreferrer">juliaup</a> and clone{" "}
          <a href="https://github.com/AdamEzzat1/julia-tutor" target="_blank" rel="noreferrer">the repository</a>.</li>
        <li>Install <a href="https://docs.docker.com/get-docker/" target="_blank" rel="noreferrer">Docker</a> and, once, run{" "}
          <code>./tutor sandbox build</code> in the repository. It builds the container your code runs in: Julia and the
          course's pinned packages, about 1 GB.</li>
        <li>Run <code>./tutor serve</code> (Windows: <code>.\tutor.ps1 serve</code>).</li>
        <li>Open the link it prints. It carries a private token in the part after <code>#</code>, which browsers never send to any server.</li>
      </ol>
      {!compact && (
        <details>
          <summary className="jt-small" style={{ cursor: "pointer", color: "var(--jt-blue)" }}>Paste the port and token instead</summary>
          <form className="jt-row" style={{ marginTop: "0.6rem" }}
            onSubmit={(e) => { e.preventDefault(); setBad(!connectManually(Number(port), token)); }}>
            <input className="jt-input" style={{ width: "6rem" }} aria-label="Port" value={port} onChange={(e) => setPort(e.target.value)} />
            <input className="jt-input" style={{ flex: 1, minWidth: 0 }} aria-label="Token" placeholder="48 hex characters from .tutor/serve-token"
              value={token} onChange={(e) => setToken(e.target.value)} />
            <button className="jt-btn" type="submit">Connect</button>
          </form>
          {bad && <p className="jt-small" style={{ color: "var(--jt-red)" }}>That is not a port and a 48-character hex token.</p>}
        </details>
      )}
      {(status.kind === "offline" || status.kind === "unauthorized") && (
        <button className="jt-btn jt-small" style={{ marginTop: "0.6rem" }} onClick={() => void checkHealth()}>Try again</button>
      )}
      <p className="jt-small jt-muted" style={{ marginTop: "0.7rem", marginBottom: 0 }}>
        The server listens on 127.0.0.1 only and answers only pages that hold its token, and it runs each piece of
        code in a fresh container: no network, a read-only system, none of your files, and limits on memory, CPU
        and processes. Without Docker, <code>./tutor serve --sandbox=none</code> runs plain processes as you, like
        typing the code into your own REPL. Chrome may ask to allow access to devices on your local network; Safari blocks pages on https from
        reaching http://127.0.0.1, so use another browser or the CLI (<code>./tutor run</code>, <code>./tutor practice</code>).
      </p>
    </section>
  );
}

export function Output({ result, error, running }: { result: RunResult | null; error: string | null; running: boolean }) {
  if (running) return <pre className="jt-output running" aria-live="polite">Running in a fresh Julia process…</pre>;
  if (error) return <pre className="jt-output err" aria-live="polite">{error}</pre>;
  if (!result) return null;
  return (
    <div aria-live="polite">
      <pre className={`jt-output ${result.ok ? "" : "err"}`}>{result.output || "(no output)"}</pre>
      {/* <img> only: an SVG shown this way cannot run scripts or reach the page */}
      {(result.images ?? []).map((im) => (
        <img key={im.name} className="jt-figure" alt={`Figure produced by the code: ${im.name}`}
          src={`data:${im.mime};base64,${im.data}`} />
      ))}
      <div className="jt-small jt-muted" style={{ marginTop: "0.3rem" }}>
        {result.ok ? "finished" : result.timed_out ? "timed out" : "ended with an error"} in {result.seconds.toFixed(1)} s
        (wall clock, including starting Julia and compiling)
      </div>
    </div>
  );
}

/** Editor + Run + output. Used by the sandbox and by "Edit and run" on examples. */
export function RunBox({ initial, env, storageKey, minRows, label }: {
  initial: string;
  env: string;
  storageKey?: string;
  minRows?: number;
  label: string;
}) {
  const [code, setCode] = useDraft(storageKey, initial);
  const { status } = useServer();
  const [result, setResult] = useState<RunResult | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [running, setRunning] = useState(false);
  const abort = useRef<AbortController | null>(null);
  const connected = status.kind === "connected";
  const envMissing = connected && !status.envs.includes(env);

  const run = async () => {
    if (!connected || running) return;
    abort.current = new AbortController();
    setRunning(true); setError(null);
    try {
      setResult(await runCode(code, env, abort.current.signal));
    } catch (e) {
      setResult(null);
      setError((e as Error).message);
    } finally {
      setRunning(false);
    }
  };

  return (
    <div className="jt-runbox">
      <Editor value={code} onChange={setCode} onRun={run} label={label} minRows={minRows} />
      <div className="jt-row">
        <button className="jt-btn primary" disabled={!connected || running || envMissing} onClick={run}>
          {running ? "Running…" : "Run"} <span className="jt-kbd">Ctrl ⏎</span>
        </button>
        {code !== initial && <button className="jt-btn ghost jt-small" onClick={() => setCode(initial)}>Reset code</button>}
        <span className="jt-small jt-muted">env: {env}{env !== "base" && course.envs[env] ?
          ` (${course.envs[env].map((p) => `${p.name} ${p.version}`).join(", ")})` : " (Julia + standard library)"}</span>
        {!connected && <ServerPill />}
      </div>
      {envMissing && <p className="jt-small" style={{ color: "var(--jt-red)" }}>Your server has no <code>{env}</code> environment. Update the repository and restart <code>tutor serve</code>.</p>}
      <Output result={result} error={error} running={running} />
    </div>
  );
}

/** A code draft that survives reloads (per key), falling back to `initial`. */
export function useDraft(key: string | undefined, initial: string): [string, (v: string) => void] {
  const storageKey = key ? `julia-tutor/draft/${key}` : null;
  const [v, setV] = useState(() => {
    if (!storageKey) return initial;
    try { return window.localStorage.getItem(storageKey) ?? initial; } catch { return initial; }
  });
  const set = (x: string) => {
    setV(x);
    if (!storageKey) return;
    try {
      if (x === initial) window.localStorage.removeItem(storageKey);
      else window.localStorage.setItem(storageKey, x);
    } catch { /* drafts last for this page view */ }
  };
  return [v, set];
}
