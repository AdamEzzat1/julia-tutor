# CLAUDE.md: julia-tutor

A symbolic (rule-based, deterministic, **no LLM in the feedback loop**) tutor
for Julia. Sibling of java-order-tutor, rust-tutor and odin-tutor, but built
from scratch. Design decisions and their reasons are in `docs/DESIGN.md`; read
it before changing scope.

## Commands

```bash
source scripts/env.sh                       # pins depot, threads, offline Pkg; defines julia_pinned
./tutor check <paths...> [--hints=N]        # static checker; exit 1 on WARN/ERROR, ADVICE never
./tutor scaffold symdiff [--check]          # (re)generate / diff starter stages
./tutor start symdiff 1 work/s1             # copy a stage to work on (work/ is gitignored)
./tutor test work/s1                        # per-testset results
./tutor explain symdiff work/s1 --hints=1   # tests + findings + measurements + where to start;
                                            # records attempts in .tutor/state.toml (--no-record), --jet adds JET
./tutor progress                            # learner model: BKT per KC, hole attempts, reviews due
./tutor fixtures symdiff [--check]          # explain on buggy fixtures vs golden outputs (~45 s)
./tutor holemap symdiff [--check]           # measured test->hole map + mutation tests (slow, ~5 min)
./tutor baseline symdiff [--check]          # measurements of the reference
./tutor lessons verify                      # run every lesson snippet on the pinned Julia
./tutor lesson L01                          # interactive lesson (state in .tutor/state.toml)
./tutor rules                               # every rule with FP risk and hints
julia_pinned --project=. test/runtests.jl   # tutor tests (TUTOR_FAST=1 skips subprocess tests)
scripts/verify_all.sh                       # definition-of-done check: everything above
```
Windows: `.\tutor.ps1 ...` instead of `./tutor`. First time on a machine:
`juliaup add $(cat JULIA_VERSION)`, then
`JULIA_PKG_OFFLINE=false julia_pinned --project=. -e 'using Pkg; Pkg.instantiate()'`
(and the same in `projects/*/reference`).

## Layout

```
JULIA_VERSION                 pinned release (1.10.13); every tool refuses any other
Project.toml, Manifest.toml   tutor env: JuliaSyntax 1.0.2, JET 0.9.14 + stdlib
src/syntax.jl                 JuliaSyntax helpers + hand-written scope resolver
src/checker.jl, src/rules/    checker core + one file per rule (JT001-JT007)
src/scaffold.jl               holes cut from reference by `# HOLE: id` markers
src/runner.jl, src/child/     fresh-process test runs (NOT a sandbox, see M3)
src/holemap.jl                measured test->hole map + mutation testing
src/explain.jl                the explain step (deterministic text + timings + observations)
src/progress.jl               learner model over time: hole-attempt evidence, BKT, `tutor progress`
src/fixtures.jl               explain fixtures and golden outputs
src/models.jl                 BKT, SM-2, Ochiai (pure functions)
src/lessons.jl, lessons/      predict-the-output lessons, verified keys
projects/symdiff/             reference/ (package), holes.toml, measure.jl,
                              holemap.toml + measure_baseline.toml (generated),
                              fixtures.toml + fixtures/*.golden.txt (generated),
                              starter/stageN (generated, never hand-edited)
docs/DESIGN.md                the four questions, project choice, instability list
```

## Stack-role group

The lead owns decisions. **Every reviewer gets a chance to object before a
milestone is called done.** Objections and their resolution go into the
milestone's PR description (template at the end).

| Role | Owns | Must object when... |
|---|---|---|
| Lead: ITS architect / tech lead | Scope, milestone order, trade-offs | Work drifts outside the current milestone |
| Julia language engineer | Reference solutions: idiomatic Julia, multiple dispatch over if-chains, concrete struct fields, type-stable functions, `!` mutation convention, no type piracy | Holes land in boilerplate instead of the concept being taught; reference code isn't idiomatic or isn't type-stable where it matters |
| Symbolic AI engineer | Symbolic projects: term representation, unification, rewriting/simplification, search, termination and confluence arguments | A rewrite system has no termination argument; a "prover"/"planner" claim isn't backed by a soundness test on known cases |
| Numerical analyst / scientific computing engineer | Scientific projects: algorithms, tolerances, convergence tests, conservation checks, floating-point honesty | A tolerance is picked to make a test pass rather than derived; a test compares floats with `==`; a "correct" solver isn't checked for its convergence order |
| PL / static-analysis engineer | Checker rules on JuliaSyntax trees, scope resolution, use of JET results, the scaffolder | A rule matches text instead of tree/scope; a rule claims type knowledge only inference can give; a rule has no negative test |
| Scientific ML engineer (from M10) | The ude project: UDE structure, adjoint method choice, AD backend, training protocol | The AD backend or `sensealg` is left to a default; a fit tolerance is called "derived" when it was calibrated; a test asserts behaviour outside the training range; gradients aren't cross-checked by a second method |
| Performance & runtime engineer | Allocation and type-stability measurement: `@allocated`, `@inferred`, JET `report_opt`, AllocCheck, thread and BLAS counts | A performance "finding" is inferred where it could be measured; a verdict depends on first-call compilation, thread count or BLAS threads |
| Test engineer | Tests as the specification, mutation testing, fixed RNG and thread count | A test checks code shape instead of behaviour; a hole passes with a trivial body; a stochastic test can flake |
| Sandbox / security engineer | Running untrusted student code safely | Any path executes student code outside the sandbox; `ccall`, `run`, Libdl, Pkg, network, eval-generated escapes aren't contained by the OS sandbox (not just a static ban) |
| Toolchain / DevEx engineer | Pinned Julia (juliaup), committed Manifests, offline depot, CI, sysimage/latency, upgrade procedure | Anything depends on "latest Julia" or an unpinned package; a Julia/package bump lands without re-verifying every lesson key and the rule suite |
| Learning scientist (reviewer) | Hint quality, fading, knowledge components, misconception-tied distractors | Level-1 hints give the answer; we measure completion instead of learning |
| Skeptic (reviewer) | Honesty | A claim ("adaptive", "catches type instability", "fast", "works") lacks a mechanism or evidence |

## Invariants (never break; each has a test or a CI check)

1. **Style tolerance.** Every rule has a test showing at least two different
   correct styles produce zero findings (`test/checker_cases.jl`, `styles`).
2. **ADVICE never changes the exit code** or blocks progress (`Checker.exit_code`).
3. **Determinism.** Same input, byte-identical checker output; findings sorted;
   no clocks, randomness or network in the checker or tests; every stochastic
   test passes an explicit, version-stable RNG (Julia's default stream is not
   stable across minor releases); Julia threads = 1 and BLAS threads = 1 (set by
   `scripts/env.sh` and the runner); never rely on Dict/Set iteration order in
   output: sort first.
4. **One pinned Julia release and one committed Manifest per environment.**
   Upgrading either is its own milestone and re-runs every lesson key and the
   whole rule suite (`verified_on` in lessons must equal `VERSION`).
5. **No answer leakage:** an opened hole contains only `error("TODO(hole:id)")`
   plus its docstring (tested in `test/runtests.jl`, "scaffolder").
6. **The starter is generated, never hand-edited.** `tutor scaffold <p> --check`
   diffs it in CI.
7. **Untrusted code never runs outside the sandbox once M3 exists.** Until M3,
   the runner is only for a student's own code on their own machine.
8. **Measured over inferred.** If a fact can come from `@allocated`, `@inferred`
   / `return_types` / JET, a convergence-order fit, or a multi-thread run, it
   does. A static rule may only *point to* the likely location.
9. **Numerical honesty.** Every numerical test states its tolerance and where it
   comes from (error bound, convergence order, conditioning). No float `==` in
   tests (the checker enforces it: JT006 is WARN inside `@test`).

Also: holes are long-form `function ... end` with a docstring that *is* the
spec; every hole has trivial bodies in `holes.toml` that must fail a test
(mutation testing in `tutor holemap --check`); every wrong lesson option maps to
a misconception; reference solutions have zero WARN findings from our own
checker; dependencies are stdlib-only unless a PR justifies a package.

## Adding things

* **A rule:** `src/rules/<name>.jl` with a `RuleMeta` (id, kc, severity, honest
  `fp_risk`, `measured_by`, three hints, `answer_tokens` that the level-1 hint
  must not contain), add it to `RULES`, and add positive/negative/style cases to
  `test/checker_cases.jl`. Match on tree kinds, never on text.
* **A hole:** put `# HOLE: id` above the function's docstring in the reference,
  add it to `holes.toml` with stage, kc and ≥ 1 trivial body, then run
  `tutor scaffold`, `tutor holemap`, `tutor baseline` and commit the generated files.
* **A lesson:** `lessons/Lnn-name.toml`; every wrong option gets a misconception
  with feedback; the hint must not contain the answer; then `tutor lessons verify`
  and set `verified_on`.

## Upgrading Julia (its own milestone)

1. `juliaup add <new>`; write it to `JULIA_VERSION`; update `[compat] julia` in
   every Project.toml.
2. Re-resolve every Manifest (`Pkg.resolve()`); JET will need a new minor.
3. `tutor lessons verify`: fix printed-output changes, then bump `verified_on`.
4. `tutor holemap <p>`, `tutor baseline <p>`; review the diffs (allocation
   counts and inferred types may move).
5. `scripts/verify_all.sh`. The PR lists every changed key, count and type.

## Milestones and definitions of done

Each milestone is done when its DoD holds, `scripts/verify_all.sh` passes, and
every role above has had the chance to object (recorded in the PR).

* **M0 Toolchain (done in slice, CI unverified):** Julia 1.10.13 via juliaup,
  committed Manifests, repo-local depot, wrappers, CI file. *DoD:* CI green on a
  clean runner (not yet run: the workflow was written without being executed).
* **M1 Vertical slice: symdiff (done):** reference + 122 behavioural tests (incl. exhaustive properties over ~2,000 small terms);
  6 holes over 2 fading stages; 7 checker rules with positive, negative and
  style tests; 2 lessons with verified keys; explain step; BKT, SM-2, Ochiai.
  *DoD:* `verify_all.sh` green; holemap shows every hole is depended on and every
  trivial body is caught.
* **M2 Explain and learner model (done except the human sign-off):** BKT per
  hole KC from test outcomes over time (one observation per distinct version of
  a hole, unambiguous evidence only: `src/progress.jl`); `tutor progress`; 7
  explain fixtures (every hole, plus a parse error) with golden outputs checked
  by `tutor fixtures --check` in `verify_all.sh`; latency report in explain;
  JET opt-in (`--jet`). *DoD:* golden-output tests (done); learning scientist
  signs off hint wording (**pending: needs a human reviewer**).
* **M3 Sandbox:** bubblewrap on Linux, Docker elsewhere (DESIGN.md §4); read-only
  depot; writable tmpfs first depot entry; no network; cgroup limits. *DoD:* the
  escape suite (DESIGN.md §4) is contained, in CI; invariant 7 enforced (the
  runner refuses unsandboxed execution of submissions it did not create).
* **M4 Second project: odeint (Dormand–Prince 5(4)).** *DoD:* convergence-order
  fit tests, tolerance-proportionality, energy drift on Kepler, exact linear
  solutions; every tolerance derived in a comment and signed off by the
  numerical analyst; ≥ 6 holes over ≥ 2 stages; holemap and mutants clean.
* **M5 More rules (measured counterparts first):** Core.Box capture (with a JET
  confirmation), `@threads` reduction race, `x == missing`, unseeded RNG in
  tests, `Array{T}(undef)` read-before-write, string byte indexing, `==` defined
  without `hash`. *DoD:* each with FP note, three hints, positive, negative and
  style tests.
* **M6 Models:** Rasch/IRT calibration of lesson items from logged responses
  (until there is data: priors only, labelled as such); tree-edit-distance
  clustering (Zhang–Shasha) of submissions on JuliaSyntax trees; execution
  traces for lessons. *DoD:* each model has deterministic tests on fixed data.
* **M7 Latency:** PackageCompiler sysimage with Test, TOML and the runner child.
  *DoD:* measured before/after numbers in the PR; adopted only if it helps.
* **M8 Julia upgrade rehearsal** (procedure above), to the next LTS when it exists.
* **M9 Third project: qsim (state-vector simulator, LinearAlgebra only).**
  *DoD:* norm preservation to a derived `c·g·eps`, gate identities, Bell/GHZ,
  QFT vs the explicit DFT matrix (n ≤ 6), dense `kron` oracle (n ≤ 5); ≥ 5 holes
  over ≥ 2 stages with zero-allocation kernels measured; a separate pinned
  `projects/qsim/crosscheck/` environment (Yao 0.9.3) agreeing on seeded random
  circuits with the qubit-order mapping stated; a benchmark *report* (not a
  test); a lesson on qubit endianness.
* **M10 Fourth project: ude (universal differential equation, SciML).**
  Requires M4 (the student's odeint) and M7 (latency). *DoD:* every package
  justified in the PR (OrdinaryDiffEq, SciMLSensitivity, one AD backend, Lux,
  Optimization, StableRNGs), with measured Manifest size, precompile and load
  time; AD backend and `sensealg` pinned explicitly; gradients checked adjoint vs
  forward AD vs central differences with derived tolerances; a hand-written
  adjoint hole matching SciMLSensitivity; stiffness measured (step counts);
  invariant 9 amended in this PR for *calibrated* fit tolerances (seed set and
  failure rate stated); simulated data only; no extrapolation asserted.
* **M11+ datalog, fvsolve, mcmc (StableRNGs.jl justified there or in M10),
  capstone bridge.**

## Known gaps (be honest about them in reports)

* The runner is **not a sandbox** (M3).
* CI has never run.
* JET loads in measurements on 1.10.13 with JET 0.9.14; if a future change breaks
  that, explain prints "unavailable" and must not guess.
* Ochiai's spectrum is the measured test-to-hole map, not line coverage.
* Latency (measured, DESIGN.md §4): `tutor test` 15–17 s, `tutor explain`
  ~20 s without JET (the default), ~110 s with `--jet`. M7 aims lower.
* Golden outputs pin allocation counts and inferred types measured on Windows;
  they should hold on Linux on the same Julia, but that is unverified until CI
  runs.
* BKT parameters for hole attempts are priors (`Progress.CODE_BKT`), not fitted
  (fitting is M6). Mastery from code is coarse: one observation per distinct
  attempt per hole, and failures shared between holes are not recorded at all.
* The allocation bench is built by the student's own `simplify`; explain only
  compares with the reference when `bench_nodecount` matches the baseline.
* Pattern matching in symdiff is positional (no AC matching); documented in
  `match_pattern`'s docstring.

## Required end-of-session report

End every session with this report (also paste it into the PR description):

```
## Session report: <date>, milestone <Mn>
Done:            <what changed, with file paths>
Verified:        <commands run and their results; e.g. verify_all.sh: PASS>
Not verified:    <what was not run and why>
Objections:      <role>: <objection> -> <resolution>   (one line each; "none raised" is allowed only if each role was considered)
Invariants:      <any invariant touched, and the test that guards it>
Measurements:    <numbers that changed: allocations, inferred types, latency>
Next:            <the next concrete step in the current milestone>
```
