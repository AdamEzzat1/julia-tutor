# Notebook mode for case work: spike and recommendation

Phase 5, feature 9. The spec asks for a spike, not a feature:

> evaluate Pluto.jl or Quarto documents for case work inside the container.
> The Sandbox/security engineer must approve any design that opens a port or
> a server. The spike's output is a written recommendation, not a merged
> feature.

Nothing in this document is wired into the tutor. The prototype it measures
lives outside the repository. Its method and numbers are below.

## Recommendation

**Do not adopt Pluto, and do not adopt Quarto's Julia engine.** If case reports
need executed code, build a small **chunk runner** on the existing sandbox
instead:

1. The `{julia}` chunks of `report.qmd` run in **one fresh child process**
   through `Practice.child`. That is the container under `--sandbox=docker`,
   exactly like a Run today. The tutor then splices each chunk's output in
   under it.
2. **Quarto renders the result with no engine**: plain markdown, so no Julia
   process starts during rendering, no server, no port.
3. **The claim checker is unchanged.** It reads the report as text and
   ignores fenced code, so spliced outputs can never satisfy a claim. Claimed
   numbers stay typed by the learner and checked against `study()`.
4. **Rendering itself runs untrusted code** (measured below: a report's
   header can name a Lua filter, and an `include` shortcode reads any file).
   So a report is rendered outside the container **only when it is the
   learner's own file on their own machine**, the same rule as `tutor run`
   and `--sandbox=none`. Rendering anyone else's report (an instructor, a
   pilot, a server) needs the renderer inside a container. That is its own
   image decision, measured below.

This design opens **no port and no server**, adds **no package and no
image**, and reuses the one execution path that is already contained and
tested. Whether to build it is the Lead's call. Today's reports have no
chunks, and the claim checker works without rendering.

## What case work needs (from the spec and docs/CASES.md)

* The student writes `study/study.jl` and `report.qmd`. The report's numbers
  are tagged (`5.18{claim:conv_order}`) and checked against what the
  student's own `study()` returns, twice, bit for bit.
* The spec says the report is "rendered inside the container". **Today it is
  not rendered at all.** Quarto is not in the images, and `Cases.check_report`
  reads the `.qmd` as text (docs/CASES.md, "Scope cuts").
* The odeint reference report has **no code chunks**. It is prose with 34
  claim tags. A "notebook" would add executed code and its output to the
  report, for exploration and for showing evidence (a convergence table, a
  plot) next to the claim.

## The constraints any design must meet

* **Invariant 7:** untrusted code runs only in the container: no network,
  read-only root, no capabilities, nothing of the host mounted, the job on
  stdin. Never add a network or a mount to the container, and never bind a
  non-loopback address.
* **Containers run with `--network=none`** (`Runner.docker_args`). A socket
  bound inside such a container is on the container's own loopback
  interface, in its own network namespace. The host cannot reach it.
* **Nothing is downloaded at run time,** and every environment is pinned
  (invariant 4). No Julia or package upgrades in this phase.

## Options evaluated

| | Pluto editor | Pluto headless export | Quarto Julia engine | Chunk runner + plain Quarto (recommended) | Status quo |
|---|---|---|---|---|---|
| Opens a server or port | **Yes**: an HTTP + WebSocket server that the learner's browser must reach | Loopback TCP to its worker (Malt), unless it runs in-process | **Yes**: a socket server (HMAC-signed) plus a socket to each notebook's worker | **No** | No |
| Can run in the `--network=none` container | Only if the port were published to the host, which invariant 7 forbids | Yes (loopback stays inside the container) | Yes (loopback stays inside the container) | Yes: it is today's Run path | n/a |
| New packages or images | Pluto + HTTP stack | Pluto, PlutoSliderServer | Quarto ≥ 1.5 in an image, plus QuartoNotebookRunner pinned (it installs itself from the network otherwise) | None to run chunks; Quarto only where rendering happens | None |
| Fits `report.qmd` and the claim checker | No: a Pluto notebook is a `.jl` file; a second report format and parser | No (same) | Yes (same file) | Yes (same file; outputs are fenced, so the checker ignores them) | Yes |
| Reactive exploration | Yes (its strength) | No | No | No | No |

### Pluto

Facts read from the source (JuliaPluto/Pluto.jl, Malt.jl, 2026-11-14):

* Pluto's editor is a web server. The browser talks to it over HTTP and a
  WebSocket.
* Notebook code runs in a `Malt.Worker` by default, a separate Julia process.
  The parent reads the worker's port from its stdout and connects with
  `Sockets.connect(port)`.
* `workspace_use_distributed = false` selects `Malt.InProcessWorker`, which
  makes plain function calls with no socket. Pluto's source marks per-notebook
  package environments "Not supported" in that mode.
* `PlutoSliderServer.export_notebook(path)` runs a notebook and writes the
  HTML export without opening a browser.
* A saved notebook is a `.jl` file in topological order. The docstring of
  `save_notebook` guarantees it runs with `julia my_notebook.jl`.

**Assessment.** The editor needs a port that the learner's browser can
reach. That is either a published container port, which invariant 7 forbids,
or Pluto running as a plain process on the host. That second case is the
learner's own code on their own machine, so it is allowed, but the tutor
cannot contain or check it. The headless export could run in the
container, but it brings a second report format (`.jl`) that the claim
checker and the case layout do not use, plus the Pluto and HTTP package
stacks. Its main benefit, reactivity, exists only in the editor.

*Learners may of course use Pluto on their own machine to explore. That
needs nothing from the tutor and is outside its guarantees.*

### Quarto's Julia engine

Facts read from the source (PumasAI/QuartoNotebookRunner.jl) and from
quarto.org's Julia page (2026-11-14):

* Quarto starts a persistent server process that loads
  QuartoNotebookRunner. The server stays alive for five minutes after the
  last worker exits.
* `serve` listens with `Sockets.listenany(8000)` (the first free port from
  8000), and every message must carry an HMAC made with a random key.
* Each notebook runs in its own worker process. The worker writes its port
  to a file, and the server connects to it over a socket.
* By default Quarto installs QuartoNotebookRunner into a private
  environment automatically. In a `--network=none` container that fails, so
  it would have to be preinstalled and pinned (`QUARTO_JULIA_PROJECT`).
* The engine ships with Quarto from pre-release 1.5.29. **This machine has
  Quarto 1.3.340.** The engine was not run, and Quarto was not upgraded
  (Phase 5 does no upgrades).

**Assessment.** Inside the container, both sockets are on the loopback of a
network namespace with no other interface, so the host cannot reach them. A
security review could accept that in principle. But this design adds
everything the chunk runner avoids:

* Quarto in a sandbox image;
* a pinned QuartoNotebookRunner;
* a long-lived server process;
* a second protocol between processes;

and all of it only to produce chunk outputs that today's child process
already produces.

### The chunk runner (prototype, measured)

The prototype is about 50 lines, run on this machine as a plain process
because Docker is not running here:

* It finds each `{julia}` chunk.
* It builds one script that prints a marker line and then evaluates each
  chunk with `include_string(Main, code)` inside `try`. Each value is shown
  as the REPL shows it; an error is printed and the next chunk still runs.
* It runs that script with `Practice.run_code(...; mode = "file")`.
* It splits the output at the markers and writes each chunk's output under
  it as a `text` block.

The sample report had four chunks:

* a trapezoid-rule error table;
* the fitted orders;
* a chunk that prints a line and then raises `UndefVarError`;
* a chunk after the error.

| Measured on this host (Windows, plain process) | |
|---|---|
| All 4 chunks, one fresh Julia process | 2.5 s |
| The error chunk | printed `a printed line`, then `ERROR: LoadError: UndefVarError: undefined_name not defined`; the next chunk still ran (`9`) |
| Quarto 1.3.340 render of the spliced markdown to HTML | 3.2 s |
| Quarto render of the odeint reference report (no chunks) | 1.7 s, then 1.5 s |
| Claim tags in the rendered HTML | printed literally (`{claim:eccentricity}`); a Lua filter could style them, which the tutor would ship as its own trusted filter |

What it does not do yet:

* chunk options (`#| echo: false`);
* inline `` `{julia} x` `` expressions (the claim checker already treats
  these as no value);
* figures. `run_code` already collects PNG and SVG files the code saves,
  so a chunk that saves a figure could have it spliced in as an image.

Running everything in one process means a chunk can depend on an earlier
one, as in a notebook. An error does not stop the chunks after it.

## The renderer runs untrusted code (measured)

Rendering is not just formatting. On this machine, with Quarto 1.3.340:

* a report whose YAML header says `filters: [marker.lua]` made Quarto run
  that Lua file during the render (the probe wrote a marker file, which
  appeared);
* `{{< include marker.lua >}}` copied that file's text into the HTML.

So a `.qmd` from someone else, rendered on the host, can run code and read
files there. Sanitising the YAML and refusing shortcodes would be an
allowlist over Quarto's whole feature set, and that is fragile. The rule
above, own file on own machine and anything else in a container, follows
the existing rule for code.

If rendering others' reports is needed, Quarto would go into an image. On
Windows its install is 268 MB (pandoc 125 MB, deno 68 MB). The base image is
0.67 GiB unpacked (docs/SANDBOX_IMAGES.md), so Quarto would add very roughly
40% to it. The Linux size was not measured. Only pandoc is needed for
markdown-to-HTML with no engine, and it is about half of that.

## Sandbox / security engineer review

| Design | Port or server? | Decision |
|---|---|---|
| Pluto editor reachable from the learner's browser | A published container port | **Rejected**: it adds a network path to the container (invariant 7). |
| Pluto editor on the host, plain process | A host loopback server | Not the tutor's to approve: the learner's own tool and own code, outside the sandbox and outside the tutor. |
| Pluto headless export or Quarto Julia engine in the container | Loopback sockets inside a `--network=none` namespace | **Not approved now.** Acceptable in principle, but only with a test showing the sockets are unreachable from the host and from other containers. Docker is not running on this machine, so that test was not written or run. Moot if the chunk runner is chosen. |
| Chunk runner on `Practice.child` | **None** | **No approval needed**: no port, no server, the existing contained path. |
| Rendering with Quarto (no engine) | None | Own report on own machine: allowed. Anyone else's report: only in a container, because a report can run Lua and read files (measured above). |

## Not verified

* Nothing ran in the container: Docker is not running on this machine. The
  chunk runner uses the same `Practice.child` call as a Run, which CI tests
  in the container, but the prototype itself was not run there.
* Quarto's Julia engine was not run: this machine has Quarto 1.3.340, and the
  engine needs pre-release 1.5.29 or later. Its behaviour above is from its
  source and documentation.
* Pluto was not installed or run (no new packages in this phase). Its
  behaviour above is from its source.
* The Linux size of Quarto or pandoc in an image was not measured.
* Whether learners want executed chunks in a case report is untested: the
  case pilot has not run (docs/CASES.md, "Pilot").

## Sources

* QuartoNotebookRunner.jl: <https://github.com/PumasAI/QuartoNotebookRunner.jl> (`src/socket.jl`, `src/server.jl`, `src/WorkerIPC.jl`)
* Quarto, Julia engine: <https://quarto.org/docs/computations/julia.html>
* Malt.jl: <https://github.com/JuliaPluto/Malt.jl> (`src/Malt.jl`)
* Pluto.jl: <https://github.com/JuliaPluto/Pluto.jl> (`src/evaluation/WorkspaceManager.jl`, `src/notebook/saving and loading.jl`)
* PlutoSliderServer.jl: <https://github.com/JuliaPluto/PlutoSliderServer.jl>
