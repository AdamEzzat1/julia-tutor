# Scientific case projects

A case project asks a real question that has a measurable answer. The
student builds the tools, uses them to answer the question, and writes a
report whose numbers software checks. Software does not check the
reasoning. The first case is `odeint` (milestone M4 in CLAUDE.md):

> Over 1000 orbits of a Kepler orbit with eccentricity 0.5, which
> integrator keeps the relative energy error below 1e-6 for fewer force
> evaluations: adaptive Dormand-Prince 5(4) or fixed-step Stormer-Verlet?
> By how much? Does the answer survive a more eccentric orbit?

```
tutor case show odeint [--rubric]     # the brief (also site/case-odeint.qmd and BRIEF.md)
tutor start odeint 1 work/m1          # milestone 1: the stage-1 holes (DP5 step, error norm, Kepler, Verlet)
tutor case check work/m1 1
tutor case start odeint work/case     # milestones 2 and 3: every hole, study/study.jl, report.qmd, BRIEF.md
tutor case check work/case 2          # adaptive solver
tutor case check work/case 3          # the study and the report
tutor case verify odeint              # authoring self-test (verify_all.sh runs it in the container)
tutor case site --check               # the site page is generated from case.toml
```

## Layout

A case is built on an ordinary hole project (`projects/<p>/holes.toml`).
The hole engine, `tutor holemap`, `tutor fixtures` and `verify_all.sh`'s
per-project loop treat it like symdiff. The case adds `projects/<p>/case/`:

| file | what |
|---|---|
| `case.toml` | the brief: question, QoI, required accuracy, emphasised method steps, an estimate prompt, data and its built-in difficulties, milestones, claims, required evidence, the robustness re-check, discussion questions, rubric, pilot, study mutants, prose for every acceptance testset |
| `acceptance/m<k>.jl` | the hidden acceptance tests, one file per milestone (never shown; a failure prints the testset's prose from `[behaviours]`) |
| `reference/study.jl`, `reference/report.qmd` | the reference study and a report with zero findings |
| `template/study.jl`, `template/report.qmd` | what the student starts from (docstrings are the specification) |
| `report_fixtures.toml` | edits of the reference report, each with the exact findings the checker must give |

The eight steps of the method name the report's sections: Question; Scales
and estimate; Model and assumptions; Method choice; Verification;
Validation; Uncertainty and sensitivity; Claims and limits. A case
emphasises some of them (odeint: method choice and verification), and the
rubric weighs those.

## How a check runs

Untrusted code runs only through `Practice.child`, with the guided-project
driver (`src/guided_driver.jl`) as the program. Under `--sandbox=docker`
(the default for `case check` and `case verify`) that is the existing
sandbox container, with no new mounts and no network. Under
`--sandbox=none` it is a plain process, for a learner's own code on their
own machine. The job is the student's `src/**.jl` and `study/*.jl` plus the
acceptance files, sent as text. The case layer adds no image, package or
mount.

* Milestones 1 and 2: the hidden acceptance tests of milestones 1..m.
* Milestone 3 (`report = true`): its acceptance tests (which call
  `study()`), then `study()` in two separate fresh processes. Each writes
  its values with exact float bits, and the two runs must agree bit for
  bit. Then the claim checker runs on `report.qmd`.

Every milestone-3 check prints the same sentence: no software grades the
reasoning, and the rubric is for the student, a peer or an instructor.

## The claim checker

`Cases.check_report` is a pure function of the report text and the values
the student's own `study()` returned. It reads `report.qmd` as text and
does not render it. Quarto is not in the sandbox images, so a value written
as inline code (`` `{julia} x` ``) is no value.

* **Sections:** one `## ` heading per method step. A longer heading that
  starts with the step's title is fine.
* **Tags:** `5.18{claim:conv_order}`, `dp54{claim:choice}`. The value is the
  number or word written right before the tag (one space allowed). Tags in
  the YAML header, HTML comments, fenced code or inline code are ignored.
* **Tolerance (the same for every claim of a deterministic study):** a
  written number w matches the computed c when |w - c| <= 0.5 * 10^k, where
  k is the decimal place of the last digit written. An integer written
  without a point must be exact. A claim may set `min_digits` (fewer
  significant digits is `claim-too-coarse` unless w == c), and may set
  `rtol` or `atol` only with a derivation in `why`. odeint sets none. Words
  match case-insensitively against a fixed list.
* **Required evidence:** groups of claims that must all be present, some
  in one paragraph. In odeint: the fitted order with its fit range, the QoI
  with its bounds, the robustness re-check, the validity range, and the
  verification results.
* **Reproducibility:** every claimed value must equal the clean re-run's
  value (`isequal`).
* **Estimates** (`{estimate:verlet_nper}`) must be present with a number in
  their section. They are never graded; the check prints each estimate
  next to the measured value.

Finding codes: `section-missing`, `claim-unknown`, `claim-no-value`,
`claim-not-computed`, `claim-mismatch`, `claim-too-coarse`,
`not-reproducible`, `claim-missing`, `claim-wrong-section`,
`evidence-missing`, `evidence-split`, `estimate-missing`.

## Estimate before you compute (Phase 5)

**Learning purpose.** Step 2 of the method asks for an estimate of scale
made *before* computing: it tests whether the learner can reason about the
problem's size from the method's order and one cheap run, and comparing it
with the measurement afterwards is feedback on that reasoning. An estimate
written after the results are known tests nothing (hindsight). A number
typed into report.qmd cannot show when it was written, so the learner
commits it first:

```
tutor case estimate <dir> verlet_nper 2e4 "one run at h = 0.05 gave 3e-5; order 2 means h about 0.0006"
```

* The commit is refused for an id the case does not have, a value that is
  not a finite nonzero number, a missing or multi-line reason (at most 300
  characters), or an id already committed: a committed estimate is final.
* It is recorded in `<dir>/.tutor-estimates.toml` with the number of study
  checks that had already run. The report milestone's check (`tutor case
  check <dir> 3`) runs the study and prints computed values, so it counts
  itself in the same file whenever the study returned values
  (`--no-record` skips this).
* That check prints, per estimate: the committed value and whether it was
  committed before the first study check ("a blind estimate") or after;
  how the learner got it; the report's value, flagged when it differs from
  the committed one; the measured value; and how far the committed estimate
  was from it in factors of ten (within 2, within 10, or off by k orders of
  magnitude, with the ratio). With nothing committed it says so and compares
  the report's estimate instead.
* Nothing here is graded or blocks a milestone.

**What it does not do.** The record is the learner's own file on their own
machine: editing it, or running study.jl outside `tutor case check`, defeats
it without being detected. It is a commitment device for the learner, not
proof for anyone else. Phase 6's opt-in log is where estimates would be
collected for a pilot.

## The authoring self-test (`tutor case verify`)

One sandboxed job runs:

* the reference against every milestone's acceptance tests;
* every trivial body in holes.toml (25 for odeint), against the acceptance
  tests of the first milestone of its hole's stage: each must fail;
* every study mutant in case.toml (6), against milestone 3: each must fail.

It also checks that every acceptance testset has its prose. Then the
reference study runs twice: it must be reproducible, the reference report
must have zero findings against it, and each report fixture (13) must give
exactly its declared findings. `validate_case` checks the brief first. Each
claim id must appear in milestone 3's acceptance file, so the hidden tests
pin down what every claimed quantity is. The prose may contain no filler
phrases and no em dashes.

## Tolerances in the acceptance tests

Each one is derived in a comment, or labelled calibrated with what it was
calibrated on. The study is deterministic: no seeds and no clock. A
"calibrated" bound is therefore one measurement on the reference, with its
margin stated, not a failure rate over seeds. Examples:

* `adaptive-eccentric-orbit` (m2): the error after one e = 0.8 period,
  calibrated on the reference at 4810 tol (tol 1e-7) and 2304 tol (1e-10).
  The bound is 2e4 tol. (The first draft extrapolated 3e3 tol from the
  e = 0.5 orbit, and measuring it showed the reference would fail.)
* `kepler-solves-the-ode` (m1): measured 4.7e-15; the bound is 1e-9.
* `step-order-nonautonomous` (m1): measured local slopes 4.92 to 4.98; the
  window is 5 +- 0.2, which excludes order 4.

## Scope cuts (said plainly)

* The report is not rendered. Quarto is not in the images, and the checker
  reads the `.qmd` as text.
* No learner state is recorded for cases. `tutor case check` prints and
  exits. BKT and progress for cases are not built.
* There is no site nav link to `site/case-odeint.qmd`: the nav files belong
  to Phase 3, and a later merge adds the link. The page is generated and
  checked by `tutor case site --check`.
* The discussion questions marked "prediction" are not graded as
  predictions yet.

## Pilot (not run)

Nothing here is evidence that the case teaches well. The pilot needs a
person and has not happened. What it needs is in `case.toml [pilot]` and
on the brief:

* one learner who knows some numerical methods and has not seen the case;
* an observer who records time per milestone, where the learner got stuck,
  every check output and every finding;
* an instructor who scores the report with the rubric, blind to the time
  data;
* a transfer task on an unseen problem;
* a decision rule for revising the scaffolding before more cases are built.

## Measurements

See the PR description for the done / measured / unverified report.
Numbers from the reference study (deterministic, identical across runs):
cost ratio 20.48 (grid bounds 20.27 to 23.00), DP5(4) at tol 3.16e-9 with
506498 evaluations, Verlet at 10372 steps per orbit with 10372001; fitted
DP5 order 5.18, Verlet 2.0004, tolerance slope 1.03; energy drift exponent
0.99 (DP5(4)) and 4.8e-7 (Verlet) over 40 to 1280 orbits; at e = 0.6 the
ratio is 19.45 and the choice holds.
