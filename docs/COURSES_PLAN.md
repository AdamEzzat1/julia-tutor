# Plan: courses, scientific cases, interactivity (Phase 0, 2026-11-10)

Status: **draft for approval.** Nothing below is built. Each number is
labelled *measured* (with where and how), *estimated*, or *not yet verified*.
Phases 1 to 7 each get their own branch and PR, ending in a Role review.

The course exists to teach scientific computing and scientific ML in Julia.
Core Julia is the way in. Business and analytics topics are out of scope.

## 0. State of the repo this plan starts from (measured)

* 48 units, 141 practice problems, 6 tracks (`Course.TRACKS`), one engine,
  one container image holding all 11 package environments.
* **CI has not passed since 2026-11-08.** The last run (aa976df) took 3 h 35
  min: about 1 h 30 to build the image, 2 h for `verify`. It failed on 4
  outputs that differ between Windows and the Linux container:
  * a `-0.0` printed by unit 36;
  * a training-dependent flag in unit 46;
  * a PCG variant in unit 33 whose verdict depended on rounding.

  The fix is a separate branch (`fix/ci-platform-outputs`), not part of this
  plan's PR. Phase 1 starts only after CI is green, because its DoD is "no
  recorded output changed".
* Docker is not running on the authoring machine. Container sizes, pull
  times and memory peaks below are therefore **not yet verified**. Phase 2
  measures them in CI.

## 1. The course split

One repo, one engine, four course catalogs. **Unit ids stay unchanged and
globally unique.** A course is a list of existing unit ids, not a renumbering.
Section 7 explains why this keeps learner state and URLs working.

| Course id | Title | Units | Problems | Status | Role |
|---|---|---|---|---|---|
| `core` | Core Julia | 01–20, plus the symdiff project | 52 | ready | the way in |
| `science` | Julia for science | 21–29 (29 is planned) | 32 | ready (29 planned) | tools for scientific work |
| `scicomp` | Scientific computing | 30–42 | 39 | ready | flagship |
| `sciml` | Scientific ML | 43–48 | 18 | **in progress** until M4 (odeint) and M7 (latency) | flagship |

The problem counts are measured from `course/units/*.toml` and add up to 141.

I kept the proposed boundaries. I considered and rejected three changes:

* **Moving 20-stdlib-tour into `science`.** Units 30 and 32 depend on it,
  and it uses only the base env. Keeping it in `core` keeps `core`
  base-only.
* **Moving 23-derivatives into `scicomp`.** Scicomp units 30, 34, 35 and 36
  and SciML units 43, 44 and 47 need it. But it uses the `calculus` env,
  which scicomp's image would otherwise not carry. It stays in `science`,
  with explicit cross-course links.
* **Moving 27-probabilistic-programming out of the path to `scicomp`.** Unit
  37 lists it as a prerequisite. Section 3 has a decision on this.

### Framing changes in `science` (Phase 3 copy, no unit content change)

The `science` course page frames each unit by the scientific work it serves.

| Unit | Framed as |
|---|---|
| 21 DataFrames | experimental and simulation data |
| 22 plotting | figures for a report |
| 23–25 | derivatives, ODEs and optimisation as model tools |
| 26 ML | the networks reused in SciML |
| 27 probabilistic programming | parameter uncertainty |
| 28 Python interop | reusing NumPy and SciPy code |
| 29 package development | shipping a reproducible tool, which Phase 7 needs |

### Guided projects (each in exactly one course)

| Project | Env | Course | Reason |
|---|---|---|---|
| derivcheck | calculus | science | builds on 23; its env is in the science image |
| epidemic | diffeq | science | builds on 24. The scicomp identifiability case (§5) extends it; that case lists it as a cross-course prerequisite |
| production | optim | science | **framing problem, see below** |
| bayesreg | turing | science | builds on 27 |
| classify | ml | science | builds on 26 |
| figures | plots | science | builds on 22 |
| tidy | data | science | builds on 21 |
| pybridge | python | science | builds on 28 |

All eight use an env that only `science` units use, so assigning any of them
elsewhere would put that env into a second image.

**Production is a business case.** It plans a factory's weekly output and
sets a price against a demand curve. That conflicts with the scope rule.
Options for the Lead:

* (a) Reframe it as a scientific resource-allocation LP with the same
  checkable duals, for example allocating beam time or reagents across
  experiments, or the power dispatch of unit 42. Recommended.
* (b) Retire it.

Unit 42 ("a circuit and an energy dispatch market") is power-systems
engineering: dual prices as marginal costs of generation. I judge it in
scope. The Research-methods instructor may disagree.

## 2. Learning outcomes

Each outcome is something a student can do, followed by what assesses it.
Units are numbers; cases and programs are named as in §5 and §6.

### `core`: Core Julia

1. Write type-stable, allocation-aware functions, and show both properties
   by measurement (`@allocated`, `@inferred`). Assessed by units 07, 08, 14,
   15 and their perf verdicts.
2. Design with multiple dispatch and parametric types instead of if-chains.
   Assessed by units 08, 09, 15 and 17, symdiff holes, and the dual-numbers
   case.
3. Implement a Base interface (iteration, indexing, broadcasting,
   `show`, promotion) so a custom type composes with generic code. Assessed
   by units 11 and 17, and the interval program.
4. Handle errors and missing values deliberately. Assessed by units 10 and
   13.
5. Write and run tests; fix a failing test from a deterministic explanation.
   Assessed by symdiff with `tutor explain`.
6. Use threads without data races, and know when not to. Assessed by unit 18
   (graded on 4 threads with repeated cases).

### `science`: Julia for science

1. Load, clean and reshape measurement data without losing information.
   Assessed by unit 21 and tidy.
2. Produce a report figure whose content (axes, series, labels) is tested.
   Assessed by unit 22 and figures.
3. Compute derivatives three ways and choose between them with a derived
   error bound. Assessed by unit 23 and derivcheck.
4. Solve an ODE model and check it against an invariant or exact solution.
   Assessed by unit 24 and epidemic.
5. Fit a model's parameters and report their uncertainty, frequentist and
   Bayesian. Assessed by units 25 and 27, bayesreg, and the Bayesian
   calibration case.
6. Package a tool so a clean environment reproduces its results. Assessed by
   unit 29 (planned) and the parameter-estimation program.

### `scicomp`: Scientific computing (flagship)

1. Predict and measure the effect of conditioning and floating point on a
   result. Assessed by units 30 and 32.
2. Measure a method's convergence order and use it to verify code (method of
   manufactured solutions, Richardson). Assessed by unit 31, the odeint case
   and the heat case.
3. Choose a linear solver, ODE method or preconditioner, and justify the
   choice with measurements (step counts, work-precision, iteration growth).
   Assessed by units 33, 35 and 36, the Robertson and Poisson cases, and the
   method-choice checkpoints.
4. Formulate a constrained or integer model whose relaxation and duals mean
   something. Assessed by units 38, 39 and 42.
5. Separate verification (is the code right?) from validation (is the model
   right?), and do both. Assessed by the odeint, heat and identifiability
   cases.
6. Quantify uncertainty and sensitivity in a QoI, and state whether the
   conclusion survives it. Assessed by unit 37, the identifiability case and
   the PK case.
7. Carry a problem through all 8 steps with little scaffolding, and write a
   report whose numbers are checked. Assessed by the scicomp capstone and the
   finite-volume program.

### `sciml`: Scientific ML (flagship, in progress)

1. Compute gradients through an ODE solve two ways and cross-check them; pick
   forward or adjoint sensitivity by parameter count. Assessed by units 43
   and 44.
2. Build a UDE that keeps the known physics, and test it inside the
   training range only. Assessed by unit 45 and the UDE case.
3. Recover a readable model by sparse regression, and measure its
   false-discovery rate against noise. Assessed by unit 46 and the SINDy case.
4. Pose a PINN loss and compare it fairly with a verified classical solver on
   accuracy and cost. Assessed by units 47 and 48 and the Burgers capstone.
5. Report a learned model's validity range, and show where it fails. Assessed
   by every sciml case report.
6. Write a training loop with a hand-written adjoint, checked against forward
   AD and finite differences. Assessed by the neural-ODE program.

The 8-step method outcomes are scicomp 5–7 and sciml 2, 4 and 5. Each step
becomes a knowledge component: `method.question`, `method.scales`,
`method.model`, `method.choice`, `method.verify`, `method.validate`,
`method.uq`, `method.report`.

## 3. Cross-course prerequisite graph

This section was generated by `scripts/course_graph.jl` from the units'
`prerequisites` fields, with the split above. Phase 1 moves the mapping into
`course/courses/*.toml` and this report into `tutor courses`.

Direct cross-course edges (46):

```
science/21 <- core/20;  science/23 <- core/15;  science/28 <- core/14;  science/29 <- core/12
scicomp/30  <- core/02, core/14, core/20, science/23
scicomp/31  <- science/24
scicomp/32  <- core/14, core/20
scicomp/34  <- core/07, core/14, science/23, science/24
scicomp/35  <- science/23, science/24
scicomp/36  <- science/23, science/24
scicomp/37  <- science/24, science/27
scicomp/38  <- science/25
scicomp/39  <- science/25
scicomp/40  <- core/14, core/18
scicomp/41  <- science/24
sciml/43    <- science/23,24,25,26, scicomp/30,31
sciml/44    <- science/23,26
sciml/45    <- science/24, scicomp/32
sciml/46    <- scicomp/30,31,32
sciml/47    <- science/23,26, scicomp/30,31,34
sciml/48    <- scicomp/31,34
```

The transitive closure gives, per course, the units it needs from others:

| Course | Needs |
|---|---|
| `scicomp` | all 20 of `core`; `science` 23, 24, 25, 26, 27 |
| `sciml` | all 20 of `core`; `science` 23, 24, 25, 26; `scicomp` 30, 31, 32, 33, 34 |

Findings from the graph that the plan has to deal with:

1. **Core's prerequisites are a chain** (each unit lists the one before it),
   so every later course "needs" all of `core`, including
   16-metaprogramming and 19-under-the-hood. That overstates the real
   dependencies.
   * **Decision for the Lead:** in Phase 1, replace the chain with the real
     dependencies, reviewed by the Curriculum architect, as its own commit.
     It changes unit metadata only, no recorded output.
   * **Or** keep the chain and label it on the site as "suggested order".
2. **SciML does not depend on 35-stiffness.** The brief assumed it would.
   43-sensitivities fits an ODE without discussing stiff solvers.
   * Recommended: add 35 to unit 43's prerequisites only if 43's text uses
     it. It currently does not, so no change.
3. **Scicomp reaches 26-machine-learning only through 27**, and 27 because
   37 lists it.
   * Unit 37 uses one fact from 27: the Monte Carlo standard error
     `std / sqrt(N)`. Its "What you need" list links to that section in 27.
     It does not use Turing.
   * Recommended: state that fact in 37 in two sentences and drop 27 from
     37's prerequisites. That is a prose change, so no recorded output moves.
     Scicomp then needs only `science` 23, 24 and 25, and it no longer needs
     the `ml` or `turing` images on its path.
   * Alternative: keep the link and accept that the path to scicomp runs
     through 26 and 27.
4. No cycles. Every prerequisite is an earlier unit (`validate_course`
   already enforces this).

## 4. Environments per course, and their sizes

| Course | Envs its units use | Image (Phase 2) |
|---|---|---|
| `core` | base (stdlib only; no Manifest), plus the tutor env for symdiff (JuliaSyntax, JET) | base |
| `science` | data, plots, calculus, diffeq, optim, ml, turing, python, base | base + 8 envs |
| `scicomp` | base, scicomp, mtk | base + 2 envs |
| `sciml` | sciml, base | base + 1 env |

**Measured on the Windows host depot (2026-11-10), not in the container.**
The counts are package source plus artifacts, computed by Julia's own
`Base.version_slug` over each Manifest. Precompile caches are counted
separately as an upper bound, because names are shared between versions.

| Env set | Packages | Package source | Artifacts | Compiled caches (upper bound) |
|---|---|---|---|---|
| scicomp + mtk | 220 | 0.10 GiB | 0.63 GiB | 1.56 GiB |
| sciml | 196 | 0.11 GiB | 1.24 GiB | 1.31 GiB |
| science (8 envs) | 540 entries, **317 not installed on this host** | – | – | – |
| all 11 envs | 600 entries | – | – | 1.74 GiB |

The science set cannot be measured on this host. The `plots` and `ml` envs
do not install with long Windows paths (CLAUDE.md, Known gaps).

**Measured in CI, image build layer times (run 42833210444).** The layers
share one depot, so each time is the cost on top of the earlier layers, not
the env alone:

| Layer | Build time |
|---|---|
| data | 105 s |
| calculus | 201 s |
| diffeq | 570 s |
| ml | 343 s |
| plots | 406 s |
| sciml | 225 s |
| scicomp | 109 s |
| mtk | 181 s |

**Not yet verified:**

* the image's total size;
* the size of each per-course image;
* pull time and memory peak per course.

The current CI does not print image sizes. Phase 2 adds `docker image
inspect` and records the numbers.

## 5. Scientific case projects (Phase 4)

### Vertical slice first: odeint (scicomp, milestone M4)

The odeint case is a Dormand–Prince 5(4) integrator written by the student,
then used on orbital mechanics.

* **Format:** holes in the M4 project format (holemap, mutants), wrapped by
  `case.toml` and `report.qmd`.
* **Question:** over 1000 orbits of a Kepler problem with eccentricity 0.5,
  does the adaptive RK method or a symplectic method keep the energy error
  within 1e-6 at lower cost?
* **Checks:**
  * fitted orders (5 and 4), with fit ranges;
  * tolerance proportionality;
  * exact solutions on a linear system;
  * energy drift growth (linear in t for RK, bounded for symplectic)
    measured against theory.
* **Claim checker tags:** `conv_order`, `drift_slope`, `qoi_energy_err`,
  `cost_ratio`.
* **Robustness:** re-run at two tolerances and a second eccentricity, and
  report whether the conclusion still holds.

This case is M4, so building it unblocks `sciml` (M10 needs the student's
odeint).

### Order after the slice

The Lead re-decides after the slice's pilot.

| # | Case | Course | Why this order |
|---|---|---|---|
| 2 | Robertson stiff kinetics: solver selection | scicomp | reuses odeint; method choice by step counts |
| 3 | Heat in a rod: MMS, CFL limit by measurement | scicomp | verification in its purest form |
| 4 | UDE missing physics (predator–prey) | sciml | builds on unit 45; extrapolation failure shown |
| 5 | Epidemic identifiability, profile likelihood | scicomp | extends the epidemic guided project |
| 6 | Dual-number forward AD | core | the core course's only case |
| 7 | Bayesian calibration with posterior predictive checks | science | coverage over a fixed seed set |
| 8 | SINDy under noise, false-discovery rate | sciml | builds on unit 46 |
| capstone | 2D Poisson at scale: direct vs iterative | scicomp | least scaffolding |
| capstone | PINN vs finite volume on Burgers | sciml | least scaffolding. Its finite-volume reference is the scicomp program's reference solution (§6), verified once |

**Cut, with reasons:**

* *symdiff stage 3 (AC matching or an e-graph).* Symbolic, not scientific
  computing. It is worthwhile but not the priority.
* *Pharmacokinetic dosing.* Unit 41 already covers it; it can be a later
  case.

### Rules for every case

* **Data:** synthetic, from a documented generator with StableRNGs, a seed,
  and the true parameters recorded; or a manufactured solution; or a
  vendored dataset with its licence file. No network at run time.
* **Each deliberate difficulty** is documented and tied to a KC: noise,
  missing observations, unidentifiable parameters, stiffness,
  ill-conditioning.
* **Report checking:** the claim checker verifies tagged numbers against the
  student's own run within stated tolerances. It also checks that the
  required evidence is present, and that a clean re-run reproduces the
  report. **The reasoning is not graded by software.** A published rubric
  covers it, and the site says so.
* **Sign-off:** the Numerical analyst signs every tolerance (derived, or
  labelled calibrated with its seed set and failure rate). The
  Research-methods instructor signs that each case has a real question, keeps
  verification and validation separate, and has a rubric that rewards
  supported claims.
* **Making the existing projects harder:** later stages get fewer hints and
  holes that span two functions. Each guided project gets a final milestone
  where the student writes the spec and tests, graded by the existing
  mutants.

## 6. Programs (Phase 7)

| Course | Program | Note |
|---|---|---|
| core | Interval arithmetic with Base integration | chosen over a sparse-matrix package: it overlaps SparseArrays less and leads into numerical honesty |
| science | Reproducible parameter-estimation tool with a CLI entry point | |
| scicomp | 1D/2D finite-volume solver for Burgers or shallow water, with a config file, verification suite and convergence report | its reference is reused by the Burgers capstone |
| sciml | Minimal neural-ODE training framework with a hand-written adjoint | requires M4 and M7 |

* **Recommendation:** the program **follows** the capstone and does not
  replace it. The capstone teaches the method with a rubric; the program
  tests whether the student can work alone. The Lead and Curriculum
  architect decide and record why.
* **The lock is honest:** self-study mode uses an encrypted bundle, a speed
  bump against accidental spoilers and not security. Cohort mode keeps the
  solutions out of the learner's copy.
* **CI mode:** decided in Phase 7, either a private submodule or a CI secret.

## 7. Risks

| Risk | What could break | Mitigation |
|---|---|---|
| Learner progress | localStorage `julia-tutor/course/v1` (keyed by unit id), `julia-tutor/state/v1`, `julia-tutor/draft/*`, and `.tutor/state.toml` | Keep unit ids unchanged, so existing keys stay valid. Add a `v2` key that adds a course index and read `v1` on first load. Phase 1 tests this on fixture state files, both CLI and web (vitest) |
| Site URLs | course.html deep links by unit id; external links to course.html | Keep course.html working as a redirect to the unit's course page, keyed by unit id |
| Recorded outputs | Outputs are keyed by code, so the split itself changes none. Per-course images could change outputs that print paths, load order or "Downloading artifact" lines | Phase 2's DoD: verify every course in its own image, with no output diff. Any diff is explained in the PR |
| CI time | already 3 h 35 min and failing; 4 images could make it worse | Base image shared and layer-cached; verify per course in a matrix (parallel jobs); push images to GHCR so verify pulls instead of building |
| GHCR publishing | needs `packages: write` and public images: outward-facing | Adam approves the workflow change and image visibility before the first push |
| `packages = []` | a problem with empty `packages` loads the whole env; in a smaller image that is faster, but it hides a missing declaration | the course verify checks each problem only imports from its course's envs |
| Cross-course units | a learner on the `scicomp` image opens unit 23 | `serve --course` refuses with a message naming the course and its image |
| Scope creep | 7 phases, each large | stop at the end of each phase; smaller and verified beats bigger and claimed |

## 8. Phase order and what each needs from Adam

| Phase | Branch | Needs from Adam |
|---|---|---|
| fix | `fix/ci-platform-outputs` | review; CI is the check |
| 1 engine | `phase1/multi-course` | decision on §3.1 (dependency chain) and §3.3 (unit 37) |
| 2 images | `phase2/course-images` | approve GHCR publishing; Docker running somewhere for local timing |
| 3 front door | `phase3/front-door` | approve copy changes |
| 4 cases | `phase4/odeint-case` | one pilot learner for the slice |
| 5 interactivity | one PR per feature | review after each |
| 6 pilot | `phase6/pilot` | recruit 3–5 + 2–3 learners |
| 7 programs | `phase7/programs` | private-solutions mode decision |

## Role review (Phase 0)

* **Lead:** no objection. Scope is a plan only; the CI fix is split out.
* **Curriculum architect:** objection: core's prerequisites are a chain, not
  dependencies. Raised as decision §3.1 and not resolved here.
* **Research-methods instructor:** no objection to the case list. Production
  is out of scope as framed; raised in §1.
* **Data steward:** no objection. No case downloads data; every generator is
  seeded with StableRNGs. A dataset licence check happens per case in
  Phase 4.
* **Interaction designer:** n/a in Phase 0 (no UI). Phase 5 features are
  listed in the brief and not re-planned here.
* **Release / infra engineer:** objection: image sizes are unmeasured. It is
  stated as such in §4, and Phase 2 measures them.
* **Julia language engineer:** n/a (no code). `scripts/course_graph.jl`
  uses only `Course.load_course`.
* **Symbolic AI engineer:** no objection to cutting symdiff stage 3 for now.
* **Numerical analyst:** no objection. The odeint question and checks are
  measurable; tolerances are derived in Phase 4.
* **PL / static-analysis engineer:** n/a (no checker change).
* **Scientific ML engineer:** no objection. sciml stays "in progress" until
  M4 and M7.
* **Performance & runtime engineer:** n/a in Phase 0. Image cold-start and
  memory are measured in Phase 2.
* **Test engineer:** no objection. The migration test on fixture state is in
  the Phase 1 DoD.
* **Sandbox / security engineer:** no objection. No docker flag changes in
  this phase. Phase 2 reviews every flag.
* **Toolchain / DevEx engineer:** objection: CI is red and slow. It is
  resolved by doing the fix branch first and listing CI time as a risk.
* **Learning scientist:** no objection. Outcomes are actions, and the 8
  method steps are KCs.
* **Skeptic:** no objection. Every number above is labelled measured (with
  where), or not yet verified. The site's "research-grade" and "spaced review
  keeps it fixed" claims (README.md:4, web/src/views/Hero.tsx:20 and :44) are
  Phase 3 work.
