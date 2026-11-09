import { useState } from "react";
import { ConnectPanel, RunBox } from "../components/Runner";
import { course } from "../course";
import { useServer } from "../server";

const WELCOME = `# A scratchpad that runs Julia on your machine, a fresh Julia for every run.
# The value of the last line is shown, like the REPL. Ctrl+Enter runs.

function collatz_steps(n)
    steps = 0
    while n != 1
        n = iseven(n) ? n ÷ 2 : 3n + 1
        steps += 1
    end
    return steps
end

println("27 takes ", collatz_steps(27), " steps")
maximum(collatz_steps, 1:10_000)
`;

export function SandboxView() {
  const { status } = useServer();
  const envs = Object.keys(course.envs).sort();
  const [env, setEnv] = useState("base");
  return (
    <div className="jt-grid" style={{ gap: "1.1rem" }}>
      <ConnectPanel />
      <section className="jt-panel jt-pad">
        <div className="jt-toolbar">
          <div>
            <div className="jt-eyebrow">Sandbox</div>
            <h3 style={{ marginTop: "0.2rem" }}>Try anything</h3>
          </div>
          <label className="jt-small jt-row" style={{ gap: "0.4rem" }}>
            Environment
            <select className="jt-input" value={env} onChange={(e) => setEnv(e.target.value)}>
              {envs.map((e) => (
                <option key={e} value={e} disabled={status.kind === "connected" && !status.envs.includes(e)}>
                  {e === "base" ? "base (Julia + stdlib)" : `${e} (${course.envs[e].map((p) => p.name).join(", ")})`}
                </option>
              ))}
            </select>
          </label>
        </div>
        <RunBox key={env} initial={WELCOME} env={env} storageKey={`sandbox/${env}`} minRows={16} label="Sandbox code" />
        <p className="jt-small jt-muted" style={{ marginTop: "0.8rem", marginBottom: 0 }}>
          Each run starts a new Julia (in a fresh container, unless <code>tutor serve</code> was started with{" "}
          <code>--sandbox=none</code>), so nothing carries over between runs and the first call of a function
          includes compiling it. The global random number generator is seeded with 42 so runs repeat; use
          <code> Random.seed!</code> or your own <code>Xoshiro(seed)</code> to choose. Runs stop after 60 seconds.
        </p>
      </section>
    </div>
  );
}
