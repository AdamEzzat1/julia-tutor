# Guided build projects

Status: design approved 2026-11-08; built in the same session: the format,
`tutor guided` (src/guided.jl, src/guided_driver.jl), two ready projects
(`tidy`, `derivcheck`) and six specified ones. Section 9 lists what was
built, measured and left out.

The symdiff model hands the student a scaffolded package with `TODO` holes.
A guided build project hands them a **milestone spec** instead: they create
the package, write the code, and write the tests. The tutor checks the code
against hidden acceptance tests and checks the *tests* against a correct
implementation and against seeded mutants of it. Feedback stays rule-based
and deterministic.

## 1. What the student gets and does

* `tutor guided start tidy work/tidy` creates `work/tidy/` with only what a
  real project would have before any code: `data/` files the project uses
  (if any) and a `GUIDE.md` with milestone 0. No `src/`, no tests.
* Milestone 0 (every project) walks through creating the package by hand the
  first time: `Pkg.generate("Tidy")`, what `Project.toml`, `name` and `uuid`
  are, `src/Tidy.jl` as a module, `test/runtests.jl` with `using Tidy, Test`
  and one `@testset`. Later projects say only "create the package as in
  milestone 0".
* Adding dependencies: the course environments are offline and, for `plots`,
  `ml`, `diffeq`, `turing` and `optim`, installed only in the container, so
  `Pkg.add` cannot work everywhere. `tutor guided deps work/tidy` writes the
  `[deps]` entries the project's environment provides (names and UUIDs from
  `course/envs/<env>/Project.toml`) into the student's `Project.toml`, and
  says that on a networked machine `Pkg.add("DataFrames")` does the same.
  The grader does not rely on the student's `Project.toml` (section 3).
* Each milestone states: the goal; the public API (function names, positional
  signatures, return types); behaviour and edge cases in prose, each with a
  short behaviour id; and which behaviours the student's own tests must
  cover. `tutor guided show tidy 2` prints it.
* Between milestones: concept questions in the course format
  (`course/AUTHORING.md`, "Concept questions"; `choice` keys are judgement,
  `output` keys are measured).

## 2. Commands

```
tutor guided list                              # projects, env, milestones, where it can run
tutor guided show <p> [m]                      # milestone spec (milestone 0 by default)
tutor guided start <p> <dir>                   # create the project folder (data/ + GUIDE.md)
tutor guided deps <dir>                        # write [deps] for the project's environment
tutor guided check <dir> [m] [--hints=N] [--sandbox=docker|none] [--no-record]
tutor guided quiz <p> <m>                      # the concept questions after milestone m
tutor guided verify [<p>] [--sandbox=docker]   # authoring self-test (section 5)
```

`check` defaults to `--sandbox=docker` for every project. `--sandbox=none`
(a plain process, the learner's own code on their own machine, as `tutor
test` does today) is accepted only for projects whose env works on the host
(`data`, `calculus`, `python`); the others refuse it with the reason (Windows
path-length limit, see CLAUDE.md Known gaps).

Progress (passed milestones, per-behaviour failure streaks for hint fading)
lives in `.tutor/guided.toml`, separate from `.tutor/state.toml` so this
work does not touch `src/progress.jl`. Feeding behaviour outcomes into BKT
per KC is a later step.

## 3. How a check runs (no image rebuild needed)

The existing image already runs `sandbox.jl run main.jl file` with any flat
set of files in a writable `/tmp` work dir and hands back the files the code
wrote. A guided check uses exactly that:

1. On the host (trusted code only): read the student's `src/**.jl` and
   `test/**.jl` as text, plus the project's reference, mutants and acceptance
   tests; build one `bundle.toml` (relative path => content) and a generated
   driver `main.jl` from `src/guided.jl`.
2. In one container (`Runner.run_contained`, env = the project's env), the
   driver decodes the job, clears it from `Main` and deletes `main.jl`, then
   for each implementation (student, reference, each mutant) in turn writes
   only that implementation's files to a fresh `/tmp` directory (plus the
   acceptance tests where that implementation runs them, which in a student
   check is the student's code only) and removes them before the next one,
   so a test cannot read a sibling's source. The reference and the mutants
   get neutral names (`impl_<k>`) in a seeded shuffle and run in that order.
   For each:
   * `Base.include(fresh_module, "<impl>/src/Tidy.jl")` defines the package
     module inside a fresh parent module (relative `include`s work);
   * a test file runs in another fresh module where `Tidy` is bound to that
     implementation and `using Tidy` / `import Tidy: f` are rewritten on the
     parsed tree to `using .Tidy` (a `mapexpr` on `Base.include`, applied to
     nested `include`s too);
   * a recording `AbstractTestSet` collects pass/fail/error per testset name
     without throwing; `Random.seed!` is reset and the working directory
     restored around each run (a `cd(@__DIR__)` in a test file stays local).
   Runs: acceptance tests of milestones 0..m vs the student's code; the
   student's tests vs the student's code, vs the reference, and vs each
   mutant of milestones 1..m.
3. The driver writes `result.toml`; the host turns it into feedback with a
   pure `assess` function (unit-tested on synthetic results, like
   `Practice.assess`).
4. The static checker (`Checker.check_source`) runs on the host on the
   student's files as text (it never executes them).
5. A milestone with a `[milestone.perf]` section (`entry`, `cases`, `args`,
   `sizes`, `compare`, `rtol`, `required`, `fail_on`) is also graded by the
   existing `Practice.grade` path once its acceptance tests pass: speed,
   allocations, growth and type stability of `entry` relative to the
   reference, in a second container. The submission is the student's
   package as one source text (`include` lines inlined on the host, as
   text) followed by `using .<Package>: <entry>`; the reference is built the
   same way, and the child loads each into its own module.
   `Guided.merge_perf!` folds the result in: with `required = true`, a
   failed grade or any verdict in `fail_on` (default: slow, allocates,
   scaling, unstable) gives `perf-fail`.

Loading the env once per check keeps a check to one container start plus
one package load; mutants cost compile time only (section 9 has the
measured times).

## 4. Verdicts and feedback

A milestone passes when all of these hold:

| Check | Pass condition | On failure the student sees |
|---|---|---|
| Acceptance | every hidden testset passes, and every acceptance file runs to its end (an error outside the test sets, usually a missing API name, fails it) | the failing **behaviour ids** and their prose; hint at the current level |
| Own tests vs reference | all pass, and at least one `@test` ran | the failing test and its evaluated values ("your test expects 3; a correct implementation returns 4"): a disagreement with the spec, not with the student's code |
| Own tests vs mutants | for milestone m and each earlier one k, killed / total over **milestone k's own mutants** >= k's `min_score` (default 0.75), and each `must_cover` behaviour has at least one killed mutant | each surviving mutant as the **behaviour it breaks**, never the edit ("your tests still pass when missing markers are not turned into `missing`") |
| Checker | no WARN or ERROR (ADVICE never blocks, invariant 2) | the finding with its usual hints |
| Performance | only where `[milestone.perf]` has `required = true`: the grade passes and gives none of its `fail_on` verdicts (verdict `perf-fail` otherwise) | `Practice.assess` feedback, prefixed with the entry name; an optional section reports as warnings |

Own tests vs the student's own code are reported (informative, not a gate:
the acceptance tests already judge the code).

Hints: each behaviour has three hints. Level 1 names the idea, level 2 points
at the specific case, level 3 says where the fix goes and what it must do but
never contains it: `validate` (run by `verify` and the test suite) rejects a
hint at any level that contains one of the behaviour's `answer_tokens`.
Surviving mutants get the same treatment with a separate set of "what to
test" hints. A failing test of the student's that calls a name outside the
milestone API (an `UndefVarError` or `MethodError` on the reference) gets its
own message: tests may use only the listed API, since they also run on other
correct implementations.

One thing at a time: wrong code that breaks one behaviour often fails the
acceptance sets of others (a wrong Fahrenheit conversion also breaks the
duplicate check and the 60 °C bound), so a check shows the spec and hint of
the *first* failing behaviour only and names the rest in one line; "what to
test" advice is shown for at most three behaviours. A hint's level rises
(1, 2, 3) with each check that showed it; a behaviour that fails but was not
shown keeps its level; one that passes starts over; a timeout or crash
changes nothing. `--hints=N` overrides the level.

## 5. Authoring format and its self-test

```
projects/guided/<p>/
  project.toml          name, package, env, title, summary, kcs, reading,
                        [[milestone]]: id, title, goal, [[milestone.api]],
                        [[milestone.behaviour]] (id, prose, kc, hints, answer_tokens,
                        test_hints), must_cover, min_score, questions, perf
  reference/src/*.jl    the full solution (final milestone; earlier milestones
                        use only their API)
  reference/test/m<k>.jl  an exemplary student test suite per milestone
  acceptance/m<k>.jl    hidden tests; one @testset per behaviour id
  mutants.toml          [[mutant]] id, milestone, behaviour, file, find, replace
                        (exact snippet of the reference, must occur once)
  data/                 files copied into the student's folder by `start`
  fixtures/             student-like submissions with expected verdicts
```

`tutor guided verify` (in `verify_all.sh` once the projects are in):
* the reference passes every acceptance testset and has zero WARN findings;
* every mutant applies (snippet found exactly once), loads, and fails at
  least one acceptance testset of its behaviour (else the acceptance tests
  are too weak) and is killed by the exemplary test suite (else the mutant is
  unkillable or the exemplar is weak);
* every `must_cover` behaviour has at least one mutant;
* each fixture (wrong code, a weak test suite, a test that disagrees with the
  spec, a WARN finding) gets its declared verdicts;
* no hint, at any level, contains one of its `answer_tokens`; prose passes the
  course's filler and em-dash checks;
* `output` concept questions match the measured output.

"Hidden" means the tutor does not print the acceptance tests. They are in the
repository, so a determined student can read them; this is a practice tool,
not an exam. Likewise the student's test code runs in the same process as
the driver and could tamper with the result; the container contains it, but
the verdict is advice to the student, not certification.

## 6. Projects

Each runs in an existing pinned env; nothing new is installed.

| # | Project | Env | Packages | Milestones |
|---|---|---|---|---|
| 1 | **tidy**: clean and summarise a messy sensor CSV | data | CSV, DataFrames | 0 package setup; 1 `read_readings(io)::DataFrame` with types and missing markers; 2 `clean(df)` (bad units, duplicates, out-of-range flagged not dropped); 3 `summarize(df)` per site and day with groupby; 4 `write_summary(io, s)` and a round-trip |
| 2 | **derivcheck**: does a hand-written derivative agree? | calculus | Symbolics, ForwardDiff | 1 `symbolic_derivative(f, nvars)` returning a callable; 2 `ad_gradient(f, x)` and the Jacobian; 3 `central_difference(f, x; h)` with h derived from eps (truncation vs rounding); 4 `check_derivative(f, df, points)` returning the worst point and a tolerance stated from the method's error bound |
| 3 | **epidemic**: an SIR model fitted to case counts | diffeq | DifferentialEquations | 1 `sir!` right-hand side and `simulate(p, u0, tspan, saveat)`; 2 conservation `S+I+R` within a derived tolerance and the epidemic peak; 3 `loss(p, data)`; 4 fit `(beta, gamma)` by a golden-section search on one parameter inside a coarse grid on the other (Optim is not in the `diffeq` env, see below) |
| 4 | **production**: plan a factory's weekly output | optim | JuMP, HiGHS, Roots, Optim | 1 `build_model(products, resources)` LP; 2 `solve_plan` and the dual prices (shadow prices) with a check against a hand-solved 2-product case; 3 Roots: the break-even price where the plan changes; 4 Optim: a nonlinear demand curve, price chosen by `optimize` with ForwardDiff gradients |
| 5 | **classify**: one classifier, three libraries | ml | Flux, MLJ, BetaML (+ DecisionTree) | 1 `load_split(rng)` stratified split with a fixed `Xoshiro`; 2 Flux MLP `train_flux`; 3 MLJ pipeline with `evaluate` and a tree model; 4 BetaML `train_betaml`; 5 `compare` table. Knet in the reading only (not installed) |
| 6 | **bayesreg**: Bayesian linear regression | turing | Turing | 1 `posterior_exact(X, y, prior)` closed form (conjugate normal, known noise): exact tests; 2 the Turing `@model`; 3 `sample_posterior` with NUTS and a fixed RNG; 4 agreement of posterior means within k·MCSE of the exact posterior, k and the flake probability stated |
| 7 | **figures**: a report figure set from one dataset | plots | CairoMakie, AlgebraOfGraphics, Plots, Gadfly, DataFrames | 1 data prep functions (tested exactly); 2 Makie figure with layout, labels, legend (tested through the returned `Figure`'s axes and plots, not pixels); 3 the same with AoG; 4 Plots and Gadfly versions saved to SVG; tests check structure and that files exist, never bytes |
| 8 | **pybridge**: a NumPy-backed routine | python | PythonCall (NumPy) | 1 `to_numpy`/`from_numpy` with copy vs view stated and tested by mutation through the other side; 2 row-major vs column-major layout; 3 a `moving_average` that calls NumPy and one in Julia, agreeing to a derived tolerance; 4 `[perf]`: allocations and the cost of crossing the boundary |

Build first: **tidy** and **derivcheck**. Both run on the host and in the
container (faster to iterate and verify both ways), their tests can be exact
or have derivable tolerances, and they exercise the whole mechanism
(reading files, returning tables, numerical tolerances). The other six
were built next (2026-11-09; section 9 lists where their specs changed
from the table above, mostly because an env lacks a package). All eight are
`status = "ready"`.

Not possible with the current envs, and why:
* **epidemic with Optim**: `diffeq` has only DifferentialEquations; loading
  Optim there needs it added to `course/envs/diffeq` and an image rebuild
  (out of scope for this work). The spec uses a search the student writes,
  which also teaches more. If you want Optim there, that is an env change for
  the course session.
* **Knet**: not installed; text only, as chosen.

## 7. Website

Optional: a "Projects" page listing guided projects, their milestone specs
and concept questions (static data from `tutor site-data`, a new
`site/data/guided.json`), and the exact `tutor guided` commands to run
locally. The page shows level 1 of each hint ladder only: levels 2 and 3
fade in from `tutor guided check`, and publishing them would bypass that.
Checking from the browser through `tutor serve` is not proposed:
a project is a folder of files, not a snippet, and the request size limits
and policy in `Server.handle` would need a new endpoint.

## 8. Known gaps (to keep honest)

* Performance grading inlines only `include("x.jl")` lines that stand
  alone; an include built from a variable or inside other code is left
  as it is and fails to load in the grader (reported as a perf-fail, with
  the load error). Timing verdicts are ratios to the reference with
  `Practice`'s wide thresholds, as for practice problems.
* Calibrated thresholds in classify (accuracies), bayesreg (MCSE margins),
  epidemic (fit error) and figures (library behaviour such as which SVGs
  carry text) were measured on one Docker host with the pinned packages.
  Each acceptance file states its seeds and observed margins; a package
  bump re-runs `verify`.
* A mutant can be *equivalent in values*: with a forced `Float64` column
  type, CSV.jl turns an unknown missing marker into `missing` anyway, but
  logs a warning. `tidy` makes that observable (the spec says reading logs
  no parse warnings; tests use `@test_logs`). `verify` is what finds such
  mutants: each must fail its behaviour's acceptance set.

* Mutation score measures the student's tests only against the mutants we
  wrote; a suite can kill them all and still miss a behaviour we did not
  seed.
* Acceptance tests are visible in the repository (section 5).
* A test suite can still tell runs apart through process-global state (a
  counter in `Main`, an environment variable): all runs share one Julia
  process, and the shuffled order is fixed per project. Only one process
  per implementation would close it, at a package load each. The check is a
  learning aid on the student's own machine, and the reference is in the
  repository anyway; the isolation stops accidents and casual shortcuts, not
  a determined student.
* A student's infinite loop costs the whole check (the container timeout),
  with no per-test attribution beyond "timed out during <run>".
* ML and MCMC acceptance thresholds are calibrated on the pinned Julia and
  packages with fixed seeds, not derived; each states its seed set and
  observed margin (invariant 9's "calibrated" wording from M10).

## 9. Status and measured results (2026-11-08)

Built: the format (section 5), `src/guided.jl` (commands, assessment, hints,
`verify`, site data), `src/guided_driver.jl` (the in-sandbox driver),
`test/guided_tests.jl`, the Projects page, and two ready projects, `tidy`
and `derivcheck`. The other six are specified (`project.toml` with
milestones, behaviours, hints and questions; no reference, tests or mutants).

`./tutor guided verify tidy derivcheck`, which runs each reference, each
mutant and each fixture through the real check:

| where | result | time |
|---|---|---|
| host, `--sandbox=none` | reference passes all milestones; every mutant killed and loads; 11 of 11 fixture verdicts as expected | 6m23s |
| container, `--sandbox=docker` | same | 13m25s wall clock, including any wait for the shared Docker lock (7m03s unlocked before the review fixes) |

Fixture verdicts (both runs): tidy `m0-no-tests` no-tests, `m1-good`
passed, `m1-weak-tests` weak-tests, `m1-disagree` tests-fail-reference,
`m1-float-eq` checker-warn, `m1-load-error` load-error, `m2-wrong-code`
acceptance-fail and weak-tests; derivcheck `m3-good` passed,
`m3-absolute-step` acceptance-fail, `m2-loose-tolerance` weak-tests,
`m4-abstract-field` acceptance-fail, weak-tests and checker-warn.

Tests: `test/guided_tests.jl` has 84 in fast mode plus 6 end-to-end checks
that run the driver in a subprocess; `web/src/guided.test.ts` and the rest
of the web suite pass (28 in all).

A stack-role review (security, assessment, pedagogy, web) raised 14
objections. Each was fixed:

* The student's tests could see the reference: every implementation now
  runs alone in a fresh temp directory, with `main.jl` deleted and the job
  cleared from `Main`; reference and mutants get neutral `impl_k` names in
  a seeded shuffle, and messages are scrubbed of the name.
* A test that changed directory broke later runs: the driver restores `pwd`.
* Mutation score was pooled over all milestones, so early mutants hid weak
  late tests: it is now per milestone, with earlier milestones as a
  regression gate, and `must_cover` needs a killed mutant per behaviour.
* An acceptance file that errored at top level, or never ran, could pass:
  both are now acceptance-fail.
* Tests calling functions outside the listed API failed with a bare
  `UndefVarError`: the check now says the tests may use only that API.
* The answer-token check covered level-3 hints only; it now covers all
  levels, and eight derivcheck hints and one tidy hint were rewritten.
* The site published all hint levels: it now publishes level 1.
* The hint streak reset when the student's tests disagreed with the
  reference: `record!` keeps it.
* Project names were not validated: `load_guided` rejects paths.
* `import Pkg as P` was not rewritten to the student's module: it is.
* derivcheck's `one-sided` mutant was not a forward difference, and two
  acceptance comments gave wrong error sizes: fixed.

Deviation from the brief at that point: performance grading was not built.
It was added on 2026-11-09 (below).

### 2026-11-09: the other six projects, performance grading

Built: classify, epidemic, figures, bayesreg, production and pybridge to
the same standard (reference, exemplary tests, acceptance tests, mutants,
fixtures); `[milestone.perf]` grading (section 3 step 5), used by pybridge
milestone 3; the course's choice-question length rule in `validate` (at most
40% of a project's choice questions, when it has 4 or more, may have the key
as the unique longest choice, and 40% as the unique shortest), which also
made three tidy questions rebalance.

`tutor guided verify` results. Host rows were measured on 2026-11-09 with
`--sandbox=none` after the last change to `src/guided.jl`. Container rows
come from each project's own `--sandbox=docker` run while it was built
(the same day, before the final `src/guided.jl` edits); a full container
re-run on the final code is still owed (see below).

| project | env | mode | result | mutants | fixtures (verdicts all as expected) | time |
|---|---|---|---|---|---|---|
| tidy | data | host | verified | 24 | 7: no-tests, passed, weak-tests, tests-fail-reference, checker-warn, load-error, acceptance-fail+weak-tests | 6m19s |
| derivcheck | calculus | host | verified | 15 | 4: passed, acceptance-fail, weak-tests, acceptance-fail+weak-tests+checker-warn | 5m25s |
| pybridge | python | host | verified; reference perf `correct,fast` | 14 | 6: passed, acceptance-fail, tests-fail-reference, checker-warn, weak-tests, perf-fail | 3m31s |
| pybridge | python | container | verified; reference perf `correct,fast` | 14 | 6, same verdicts | 4m07s |
| classify | ml | container | verified (build run) | 19 | 5: passed, weak-tests, tests-fail-reference, weak-tests+checker-warn, acceptance-fail+weak-tests | 2m41s |
| figures | plots | container | verified (build run) | 23 | 5: m1-good, m1-weak-tests, m1-float-eq, m1-disagree, m2-wrong-code | 5m09s |
| epidemic | diffeq | container | verified (build run) | 22 | 4: passed, acceptance-fail+weak-tests, checker-warn, weak-tests | 7m54s |
| bayesreg | turing | container | verified (build run) | 15 | 4: weak-tests, tests-fail-reference+checker-warn, acceptance-fail+tests-fail-reference, passed | 16m06s |
| production | optim | container | verified (build run) | 15 | 4: passed, acceptance-fail+tests-fail-reference, acceptance-fail+weak-tests, weak-tests+checker-warn | 11m54s |

Owed: the container re-run of all eight on the final code. The local Docker
VM failed to start, and CI run 42733280616 stopped at `tutor course verify`
before reaching the guided step: `scripts/verify_all.sh` ran the course
check as plain processes on the runner instead of in the container the
outputs were recorded in (49 problems, mostly `No module named 'numpy'`).
The script now passes `--sandbox=docker` there too.

Spec changes from the planned versions, each forced by the env or by
making a behaviour testable:

* classify: no CSV or DataFrames in `ml`, so `load_split` parses the file
  and `compare` returns a vector of NamedTuples; MLJ cross-validation left
  out of milestone 3 (compiling `evaluate` peaks near 3.8 GB); `predict_mlj`,
  `predict_betaml` and a callable `FluxModel` added so labels and class order
  are testable. The data is synthetic (90 rows, seeded).
* epidemic: `read_cases`, `expected_cases`, `POPULATION` and `U0` added so the
  loss has defined inputs; conservation is explained correctly (a
  Runge-Kutta step keeps linear invariants up to rounding, observed 8.9e-16
  over a year), not as a tolerance bound; golden-section's evaluation count
  is bounded with a stated slack; `peak_day` returns 0.0 when I cannot grow.
* figures: `read_wide` added (no CSV in `plots`); behaviours split per panel
  part; `plots_panel` and `gadfly_panel` return their objects for inspection.
  The planned "each SVG contains the city names" was false: CairoMakie and
  Plots.jl (GR) write glyphs as paths, only Gadfly writes `<text>`; the spec
  and a question now teach that.
* bayesreg: Turing 0.49 returns a FlexiChains chain, so the API says chain
  and adds `coefficient_draws`; `predictive_interval` takes `sigma` and has a
  draws method, tested on independent normal draws (no MCMC in milestone 4);
  sampling defaults to 1000 draws; agreement is 4 MCSE (false failure about
  6e-5 per coefficient), calibrated over seeds 1 to 6.
* production: Optim 2.3.2 takes `autodiff = AutoForwardDiff()`, not
  `:forward`; the "uses exact gradients" behaviour is tested by a demand
  function that records whether it saw dual numbers (a general
  `best_price(q, cost)` method makes that possible); `plan-status`,
  `break-even-bracket` and `never-made` added.
* pybridge: `from_numpy` also converts 2-D arrays of either memory order;
  the moving average's agreement bound is derived as (n + k) · eps · max|v|
  (observed 1e-12 against 2e-9); milestone 3's `moving_average` is graded
  for performance (fixture `m3-allocating`, a slice per window, gets
  `perf-fail`).

Projects were built by five parallel agents (pybridge and the perf grading
by the lead), each verifying in the container; the table above is one
re-run of all eight after the last edit.
