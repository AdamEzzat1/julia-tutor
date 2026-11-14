# Writing course units

The course goes from absolute basics to advanced Julia and its ecosystem. Each
unit is one TOML file in `course/units/`, named `NN-slug.toml` (the number sets
the syllabus order). `course/units/01-first-steps.toml` is the worked example
of the format; `src/course.jl` is the loader and the validator.

Nothing a learner sees as "the output" is typed by hand, and no performance
claim is untested:

```bash
./tutor course record 05          # run every example, store outputs in course/outputs/05-*.toml
./tutor course verify 05          # re-run examples, then grade each problem's reference, starter and variants
./tutor course verify 05 --no-grade   # examples and structure only (fast)
./tutor run file.jl               # run a file exactly as the sandbox does
./tutor practice <problem-id> file.jl # grade a solution as the website would
./tutor site-data                 # regenerate site/data/ (courses.json, course-<id>.json) after recording
```

Review the recorded outputs (`course/outputs/<unit>.toml`) before committing:
they are what the website shows under each example.

## Unit fields

```toml
id = "05-functions"              # must equal the file name without .toml
title = "Functions"
track = "foundations"            # foundations | core | advanced | ecosystem
env = "base"                     # course/envs/<env>; base = Julia + stdlib only
status = "ready"                 # or "planned" (then only `outline` is needed)
summary = "One or two sentences."
kcs = ["functions", "closures"]  # knowledge components (kebab-case)
prerequisites = ["04-control-flow"]   # earlier units: bare id = same course; "core/20-stdlib-tour" = another course (must be in its `requires`)
lessons = ["L01-dispatch"]       # optional: predict-the-output lessons in lessons/
outline = []                     # planned units: bullet points of what they will cover

[[section]]
title = "..."
body = '''
Markdown. Inline `code`, **bold**, *italic*, [links](https://docs.julialang.org),
fenced ```julia blocks, bullet lists. Keep paragraphs short.
'''

  [[section.example]]
  caption = "Optional one-liner shown above the example."
  notice = "Optional: what to look at in the result, shown under the output and figures (\"Notice ...\")."
  code = '''
x = 1
x + 1
'''
  # check = false   -> output varies between runs (timings); recorded, not compared
  # mode = "file"   -> run with file (include) semantics instead of the REPL's soft scope
```


## Environments

`env` names a directory in `course/envs/` with a committed Project.toml and
Manifest.toml. Current ones: `base` (stdlib), `data` (DataFrames, CSV),
`plots` (CairoMakie, AlgebraOfGraphics, Plots, Gadfly, DataFrames),
`calculus` (ForwardDiff, Symbolics), `diffeq` (DifferentialEquations),
`optim` (JuMP, HiGHS, Optim, Roots, ForwardDiff), `ml` (Flux, MLJ, BetaML,
DecisionTree, MLJDecisionTreeInterface, MLJLinearModels), `turing` (Turing),
`python` (PythonCall, with the system Python and NumPy; no CondaPkg),
`sciml` (OrdinaryDiffEq, SciMLSensitivity, Lux, ComponentArrays, Optimization,
OptimizationOptimisers, OptimizationOptimJL, ForwardDiff, Zygote, StableRNGs),
`scicomp` (LinearSolve, Krylov, IncompleteLU, SparseArrays, OrdinaryDiffEq 7,
StochasticDiffEq, DelayDiffEq, ForwardDiff, JuMP, HiGHS, Ipopt, OhMyThreads,
KernelAbstractions, BenchmarkTools, StableRNGs), `mtk` (ModelingToolkitBase,
ModelingToolkitStandardLibrary, OrdinaryDiffEq; MIT-licensed parts only: full
ModelingToolkit's index reduction is AGPL, see docs/SCICOMP_PLAN.md).
Adding a package is a change to the Manifest: it rebuilds the sandbox image
(`tutor sandbox build`) and must be justified in the PR.

A Run in an environment other than `base` may take up to 180 s (loading a
large package and compiling its first call); examples get 240 s when
recorded. Keep examples small anyway: a learner waits for each one. On
Windows with a long checkout path, `plots` and `ml` cannot be installed in
the repo-local depot (artifact paths exceed 260 characters); use
`--sandbox=docker` for those units.

## How examples run

Each example runs alone in a **fresh Julia process** (`src/child/sandbox.jl`),
exactly like the sandbox's Run button:

* REPL semantics: the value of the last expression is displayed with
  `show(stdout, MIME"text/plain"(), x)` unless the code ends with `;`, and
  top-level loops use REPL soft scope. Use `mode = "file"` to show what
  happens in a script instead.
* Errors print as `ERROR: <message>` plus `@ <function> at line N` for frames
  in the example's own code. An example may end in an error on purpose.
* The global RNG is seeded (`Random.seed!(42)`) before the code runs, so
  `rand()` is reproducible. Prefer an explicit `Xoshiro(seed)` when teaching.
* Examples must be **self-contained** (no state shared between examples) and
  **identical on Windows and Linux**: no file paths, `pwd()`, `homedir()`,
  `Sys.iswindows()`, memory addresses, `objectid`, timings or thread counts in
  checked output. Use `check = false` for anything that varies, and say so.
* Output must be short. Large arrays are fine: display truncates them.
* stderr is captured too (warnings, `@warn`), interleaved with stdout in an
  order that depends on buffering. If an example prints both, make the
  warning come first (or last) so the order cannot change.
* `InteractiveUtils` is not loaded (as in a script): examples using
  `@code_typed`, `@which` or `subtypes` need `using InteractiveUtils`.

## Figures

A unit in the `plots` environment (or any unit whose packages draw) can show
figures. Two ways, both recorded by `tutor course record` and shown on the
site under the example's text output:

* End the example with a figure value: a Makie `Figure`, a Plots.jl plot, a
  Gadfly plot or an AlgebraOfGraphics `draw(...)` result. Instead of printing
  it, the child saves it as `figure.png` (or `figure.svg` when the value
  only renders as SVG, like Gadfly) and prints `[figure: figure.png]`.
* Save files yourself: every `.png` and `.svg` the code writes in its
  working directory comes back (sorted by name, at most 4, 3 MB each), e.g.
  `save("fit.png", fig)` or `savefig(p, "fit.png")`.

Image bytes are not compared by `verify` (font rendering differs between
machines); only which figures exist is. Record figures in the container
(`--sandbox=docker`) so the committed PNGs come from Linux, like CI's. Keep
figures small (`size = (600, 350)` in Makie, `size = (600, 350)` in Plots):
they are committed. Plain data (arrays, strings, numbers) is never drawn.



## Analogies, diagrams and references

Three optional additions that make a unit easier to follow without loosening
it. All are checked by `Course.enrichment_problems` (part of
`tutor course validate`) and shown on the site beside the section's prose.

```toml
[[section]]
title = "..."
body = '''
...
'''
refs = ["raissi-2019"]          # right after `body`: ids from the unit's [[reference]] list

  [[section.diagram]]
  file = "pinn-loss.svg"        # course/diagrams/<unit-id>/pinn-loss.svg
  alt = "What the picture shows, in words (40+ characters)."
  caption = "One sentence: what to notice."

  [[section.analogy]]
  title = "A tailor fitting a suit"
  text = '''Markdown.'''
  breaks = '''Where the analogy stops matching the mathematics (required).'''

[[reference]]                   # at the end of the file
id = "raissi-2019"              # lowercase kebab-case, unique in the unit
authors = "Raissi, M.; Perdikaris, P.; Karniadakis, G. E."
title = "..."
venue = "Journal of Computational Physics 378"
year = 2019
url = "https://doi.org/10.1016/j.jcp.2018.10.045"
note = "What in this unit it supports."
```

* **Analogies** sit beside a definition, never in place of one. `breaks` is
  required: a sentence or more on where the picture stops being true. An
  analogy must not imply something false (a network "understanding"
  physics, a method "always" being faster).
* **Diagrams** are hand-written SVG shown with `<img>` on a white card in
  both themes. `svg_problems` refuses scripts, event handlers, links other
  than `#local` ids, `<image>`, `<foreignObject>`, `@import` and external
  `url(...)`, and needs a `viewBox` and a `<title>`. A bare `<` or `&` in
  text is refused too (write `&lt;`, `&amp;`): the browser shows nothing for
  an SVG that is not well-formed XML. Files must be used by a
  section, and stay under 64 kB. Every number in a diagram comes from the
  unit's recorded outputs or the mathematics; schematic curves say so.
  `tutor site-data` copies `course/diagrams` to `site/assets/diagrams`.
* **References** are public (https; an arXiv copy when the journal is
  paywalled) and were fetched and checked when added: title, authors and
  year against Crossref (`https://api.crossref.org/works/<doi>`) or the
  arXiv abstract page. Every reference is cited by a section, and its
  `note` says what it supports. CI does not fetch links (no network in the
  checks); the check is at authoring time and in review.
* Add, do not rewrite: progress on the site is keyed by section and example
  position, so a new idea goes at the end of a section's body or in these
  tables, never as a new section in the middle.

## Concept questions

Each section can end with questions that check understanding of what the
section taught, not recall of syntax. They appear under the examples, the
learner picks until right, each wrong pick shows the misconception it stands
for, and the explanation comes with the answer.

```toml
  [[section.question]]
  kind = "choice"                 # or "output"
  prompt = "Why does `ODEProblem` take the time span and not a list of times?"
  choices = [
    "The solver picks its own steps; `saveat` asks for output at given times",
    "Julia cannot store a vector of times in a struct",
    "Time spans are faster to pass than vectors",
  ]
  answer = 1                      # 1-based
  explain = "Adaptive solvers choose step sizes from the error estimate..."
  misconceptions = [
    "",                           # the answer gets ""
    "Structs hold vectors fine (`Vector{Float64}` fields are common); the reason is adaptivity.",
    "Speed is not the point: the steps are an output of the solver, not an input.",
  ]

  [[section.question]]
  kind = "output"
  prompt = "What does this print?"
  code = '''
using ForwardDiff
ForwardDiff.derivative(x -> x^3, 2.0)
'''
  choices = ["12.0", "8.0", "6.0"]
  answer = 1
  explain = "d/dx x^3 = 3x^2, which is 12 at x = 2; the result is exact, not a finite difference."
  misconceptions = ["", "That is f(2), the value, not the derivative.", "3x at x = 2: the exponent was dropped."]
```

* `output` questions are keyed by measurement: `record` runs `code` like an
  example (REPL display), and `verify` fails unless the right choice is
  exactly the output (trailing whitespace aside) and no other choice is.
  Make wrong choices plausible outputs, each tied to a real misconception.
* `choice` questions test a concept: what a package is for, when to pick one
  tool over another, why a result came out the way it did. A good question
  has one defensible answer; avoid "all of the above" and trick wording.
* Every wrong choice needs its misconception (`validate` enforces it), in
  the same voice as hints: say what the learner probably thought, then why
  it is wrong, without restating the whole answer.
* 2 to 6 choices. Vary the position of the answer across a unit.
* Do not let length give the answer away. Drafts tend to pair a careful,
  qualified key with short strawmen, and learners notice. State the key's
  claim briefly (the reasoning goes in `explain`) and make each distractor as
  specific. `validate` fails a unit where the answer is the unique longest
  choice in more than 40% of its choice questions.

## Predict, then run

**Learning purpose.** A prediction made before seeing a result tests the
learner's model of the method: the order a convergence plot will show, which
side of a stability limit a step is on, whether a stable method keeps a sign.
Reading the output first and then agreeing with it tests nothing. So the site
hides an example's output (with its figures and notice) until the learner
commits one choice. It scores that first pick only, and counts hits per
knowledge component in the browser. A concept question differs: the learner
picks until right, and it comes after the examples.

```toml
  [[section.example]]
  caption = "..."
  code = '''
...
'''

    [section.example.predict]
    kc = "convergence-order"            # one of the unit's kcs: the hit rate counts for it
    prompt = "RK4 is a fourth-order method. Before the output is shown: what observed order does it give between 10 and 20 steps?"
    choices = ["About 4 (3.95 or more)", "Between 3.5 and 3.95", "Below 3.5"]
    measure = 'RK4   errors [^\n]*\n +orders \[([0-9.]+)'   # one capture group, read from the recorded output
    ranges = [[3.95, inf], [3.5, 3.95], [-inf, 3.5]]        # choice i holds when lo <= value < hi
    answer = 3
    explain = "The order describes small `h`..."
```

* The key is measured, not typed. `measure` is a regular expression with
  one capture group, applied to the example's recorded output. For a
  numeric prediction, give `ranges`, one half-open `[lo, hi)` per choice,
  with no overlaps. For a word, give `values`, one per choice, compared
  case-insensitively (for example `values = ["true", "false"]` against a
  printed `true`). `verify` fails unless exactly one choice holds and it is
  `answer`, so a re-recorded output that changes the result breaks the
  key, just as it breaks an `output` question.
* The example must be checked (`check = true`, the default): a key read from
  an output that `verify` never compares could change unnoticed.
* Pick an example whose result the earlier output on the page does not
  already show. A prediction answered by the example just above it measures
  reading, not reasoning.
* `explain` is shown with the output whatever was picked, so write it for
  the learner who missed: say why the measured value came out where it did.
* `site-data` exports a prediction only when its key holds, together with
  the measured value, which the page shows next to the answer.

## Method-choice checkpoints

**Learning purpose.** Choosing a method is step 4 of the scientific method the
cases teach, and the step learners most often skip: they take the default,
or the one they used last. A checkpoint makes the learner commit a solver,
step size or preconditioner and say why in one line, before the measurements
are shown. Then the measurements score the choice. The reason is not graded
(nothing in the tutor can judge free text, and no model is asked to). The
page shows it back next to the counts, so the learner can see which part of
their reasoning held. Like a prediction, the first commit is the only one
scored, and good choices are counted per knowledge component in the browser.

```toml
    [section.example.choose]
    kc = "stiffness"                     # one of the unit's kcs
    prompt = "The heat equation on 199 points ... Which solver do you run?"
    choices = ["`Tsit5`: ...", "`Rodas5P`: ...", "`FBDF`: ..."]   # the table shows the text before ": "
    rows = [                              # one regex per choice, matched in the recorded output
      'Tsit5 +naccept \d+ +njacs (\d+) +nw (\d+) +nf (\d+)',     # numbered groups: summed into the cost
      'Rodas5P +naccept \d+ +njacs (\d+) +nw (\d+) +nf (\d+)',
      'FBDF +naccept \d+ +njacs (\d+) +nw (\d+) +nf (\d+)',
    ]
    cost = "right-hand-side calls + Jacobians + factorizations (...)"   # what the cost counts, shown in the table
    band = 2.0                            # good = within 2x of the cheapest choice that meets the accuracy
    good = [2, 3]                         # must equal what the measurements give
    explain = "..."
    misconceptions = ["Each `Tsit5` step is cheap, but ...", "", ""]  # required for every choice that is not good
```

* The verdicts are measured, not typed. Each row's numbered capture groups
  are summed into that choice's cost. A row may also have a group named
  `ok` (`(?<ok>true|false)`): a choice whose `ok` is not `true` misses the
  accuracy the example asks for, and *fails*. Among the rest, a choice
  within `band` times the cheapest is *good* and the others are *costly*.
  `verify` fails unless the good set equals `good`.
* The cost is a count (steps, calls, iterations, factorizations), never
  wall time, which varies by machine and load. Say in `cost` what it leaves
  out (a linear solve, building a preconditioner), so the learner does not
  read the count as the whole price.
* **No verdict near the edge.** `verify` also fails if any choice that meets
  the accuracy costs within a factor of 1.5 (`Course.CHOICE_MARGIN`) of the
  band's edge, either side. A choice at 2.2× with a band of 2 could flip with
  a 10% drift in its count. That is why a checkpoint may sit on a
  `check = false` example, whose counts move a little between CPUs and
  package builds: `verify` re-runs the example and checks the verdicts on
  the fresh output, though it does not compare the digits.
* An example carries a prediction or a checkpoint, not both.
* Give two to six choices that a learner could defend, and phrase each as
  what the method does, not as a verdict. The page lists the choices before
  the output, so the choice text must not give the counts away.

## Break it

**Learning purpose.** Knowing a method's conditions is not the same as
knowing where they bite. A break-it challenge asks for the value of one
parameter (a step size, a start point, a rate ratio) at which a method stops
working: it goes unstable, stops converging, or can no longer identify its
parameters. The learner may derive the edge from the section, or measure it
by running the challenge's *probe* at values of their choice through
`tutor serve`. Then they commit one value, and the recorded sweep shows where
the edge is. Like a prediction, only the first commit is scored, and edges
found are counted per knowledge component in the browser.

```toml
    [section.example.breakit]
    kc = "stability"                       # one of the unit's kcs
    prompt = "... Find the largest step `h` at which ..."
    param = "h"                            # the parameter's name, as the learner types it
    measure = "|u| after 100 steps (from 1)"   # what the row's number is (a column header)
    row = 'h = (?<p>\S+) .*\|u\| after 100 steps = (?<m>\S+)'   # named groups p and m, matched on every line
    fails = "above"                        # the method failed where m > limit ("below": m < limit); NaN fails too
    limit = 1.0
    edge = [0.23, 0.25]                    # must equal the two swept values either side of the change
    close = 1.25                           # a value within this factor of the edge is "close"
    probe = '''
    ... the same computation at one value: h = {{p}} ...
    '''
    explain = "..."
    short = "..."                          # shown for a value where the method still works
    past = "..."                           # shown for a value well past the edge
```

* The edge is measured, not typed. The example's output is a sweep, one line
  per value; sorted by `p`, the method must change from working to failing
  exactly once (at least 4 rows). The values either side of that change are
  the measured edge, and `verify` fails unless it equals `edge`.
* The example must have `check = true`: the edge is read from digits, so the
  output must be one that `verify` compares.
* Sweep finely near the edge: `edge` may span at most a factor `close`, so a
  value inside it is a real answer and not a lucky region. Choose the sweep's
  range so the measurement is monotone over it. If the method also fails far
  on the other side (precision is lost both when two rates merge and when one
  phase ends before the first sample), keep the sweep on one side and say so
  in `explain`.
* **The probe is checked too.** `verify` runs `probe` at both ends of `edge`
  and fails unless each prints one `row` line, the method works at one end
  and fails at the other, as in the sweep. So a learner's probe run measures
  the same thing as the sweep. The site puts the learner's value into the
  probe only after checking it is a plain positive number, and the run goes
  through `tutor serve` like any other.
* `limit` is a convention, not a law (a relative standard error of 0.5, a
  growth above 1): state it in `prompt`, so the learner knows what "fails"
  means before measuring.
* An example carries one of a prediction, a checkpoint or a break-it
  challenge.

## Precomputed explorers

**Learning purpose.** Some results are a surface rather than a number: an
error against the step size for three methods, a growth factor against a
stability number on three grids. A table of 60 rows is hard to read, and
the static site cannot run Julia. An explorer puts a slider on each axis
of a grid that the example's output already recorded, shows the value at
the chosen point exactly as it was printed, and plots the measure against
one axis. It is labelled "precomputed by the reference; run it yourself
with tutor serve": the example's "Edit and run" box runs the same code at
other values. Nothing is scored or stored.

```toml
    [section.example.explore]
    kc = "convergence-order"               # one of the unit's kcs
    prompt = "Pick a method and move `h`. ..."   # what to try with the sliders
    row = '(?<method>\S+) +h = (?<h>\S+) +error = (?<err>\S+)'   # a named group per axis, and the measure's
    measure = "err"                        # the measured group
    label = "error at t = 2"               # what the measure is
    log = true                             # the measure on a log scale (values must not be negative)
    x = "h"                                # the axis on the plot's horizontal (numbers, at least 3 values)
    series = "method"                      # optional: one line per value of this axis
    explain = "..."                        # shown under the explorer

      [[section.example.explore.axis]]     # 1 to 3 axes, in the order the controls are shown
      group = "method"
      label = "method"                     # an axis of words gets buttons, in the order the output prints them

      [[section.example.explore.axis]]
      group = "h"
      label = "step size h"
      log = true                           # numbers get a slider, sorted ascending
```

* **The grid is the output.** Every line that `row` matches is a point. The
  matched lines must form a full grid: every combination of the axes' values
  exactly once, at most 400 points, each axis with at least 2 values, the
  measure a number (`Inf` and `NaN` count; the site draws what the scale can
  hold and the table shows the rest). `verify` checks this on the recorded
  output, and `tutor site-data` exports only a grid that passes.
* The example must have `check = true`, so `verify` compares every printed
  value. Keep the grid where the digits are the same on every CPU: `sum`'s
  `@simd` blocks and values near the rounding floor (`exp` and `sin` use
  `muladd`, a fused multiply-add on some CPUs only) can move the last digits.
  Unit 31's grid stops at `h = 0.0125` for this reason, and unit 30's writes
  pairwise summation out instead of calling `sum`.
* Print each axis value one way only (`0.1`, not sometimes `0.10`), and
  round the measure to the digits the explanation needs. `@printf "%.3g"`
  avoids the binary representation error that `round(x; sigdigits = 3)`
  shows on large numbers (`9.360000000000001e44`).
* **Every number in `prompt`, `notice` and `explain` is measured.** When both
  the x axis and the measure are on log scales, the site also shows the
  slope between the chosen point and its neighbour, computed from the printed
  values. Check the prose against that slope: a claim such as "the slope is
  below 4 at coarse steps" has to be the one the grid shows.
* An explorer may follow a prediction on the same example (the explorer
  appears with the output, once the prediction is committed), but not a
  checkpoint or a break-it challenge, which are grids of their own.

## Practice problems

```toml
[[problem]]
id = "count-vowels"              # unique across the course, kebab-case
title = "Count the vowels"
difficulty = "warm-up"           # warm-up | core | stretch
kcs = ["strings"]
entry = "count_vowels"           # the function the learner defines
prompt = '''Markdown task statement with an example call or two.'''
starter = '''
function count_vowels(s)
    # your code here
end
'''
reference = '''hidden reference solution (idiomatic, fast, type-stable)'''
cases = ["\"hello\"", "\"\"", "\"AEIOU xyz\""]    # argument lists as Julia source; shown to the learner
gen = "rng -> [(randstring(rng, 'a':'z', rand(rng, 0:30)),) for _ in 1:20]"  # seeded random cases
compare = "isequal"              # or "isapprox" (with rtol = 1e-8)
check_type = true                # result type must equal the reference's
compare_args = false             # true for in-place functions: mutated arguments are compared too
hints = ["first hint, never the answer", "more specific"]

  [problem.perf]
  args = "randstring(rng, 'a':'z', n)"   # arguments for timing, with `rng` and `n` in scope
  sizes = [1000, 32000]          # one size, or two (two estimate the growth exponent)
  mutates = false                # true when the function changes its arguments

  [[problem.variant]]            # the grader's own tests: at least one must be "incorrect"
  label = "counts only lowercase"
  code = '''...'''
  expect = ["incorrect"]
```

`cases`, `gen` and `perf.args` are evaluated in a module with `Random` and
the unit environment's packages loaded (so a `data` unit can build a
DataFrame as an input). A case's text goes inside the call parentheses:
`"[3, 1, 2], 2"` means `entry([3, 1, 2], 2)`. Arguments are positional only:
a case cannot pass keyword arguments, so a problem's entry should take
positional ones. Several `perf.args` are written like call arguments,
`"randn(rng, n), randn(rng, n)"`, **without** enclosing parentheses (that
would pass one tuple). Use `gen` for broad coverage and keep `cases` to the
few calls a learner should read.

Problems about threads set `threads = 4` (grading runs Julia with that many
threads; 1 by default) and `repeats = 10` (every case runs that many times
and must give the reference's answer every time). Add at least one case large
enough for tasks to overlap, e.g. `"collect(1:1_000_000), 8"`, and a racy
variant expected `["incorrect"]`: on several threads a lost update shows up
within a few runs. The feedback then explains data races.

### The performance ladder

Every grade also reports three rungs, climbed in order (`Practice.ladder`,
derived from the same measurement as the verdicts; nothing to author):

1. **Correct**: every case passes.
2. **Within 2× of the reference's time** at the largest `perf.sizes` (the
   ratio from the same interleaved samples as the speed verdict). This is
   looser than the "on par" verdict (1.75×), on purpose: the rung is a goal
   a learner can reach, not a benchmark. Near 2× a rerun can land on either
   side, and the text says so.
3. **Allocation-free**: zero bytes per call at *every* perf size. Offered only
   when the reference itself allocates nothing at every size. A reference
   that returns a new array, or allocates a few bytes, leaves this rung "not
   offered", never "impossible". To offer it, write the reference
   allocation-free (an in-place `!` function, a loop instead of a temporary).

A problem without `[problem.perf]` offers rung 1 only. The site keeps each
problem's best climb in the browser (`julia-tutor/course/v1`, key `ladder`);
there is no ranking and nothing is sent. In the base environment (60 problems,
measured 2026-11-14), 29 offer three rungs, 29 two, and the 2 Parsons problems
one; every reference climbs its full ladder.

Results without a meaningful `isequal` (a figure, a fitted model, a chain of
samples, a JuMP model) use `compare = "custom"` with a `checker`, a function
`(got, expected) -> Bool` written as Julia source and evaluated with the
problem's packages loaded. Prefer returning plain numbers from the entry
instead; use a checker when the object *is* the point (a `Figure` with two
axes, an `ODESolution` that reaches the right final state). Set
`check_type = false` when the checker accepts several types.

`packages = ["Roots"]` limits what the grading job loads for cases, `gen`
and the checker (default: every package of the unit's environment). Large
environments (`ml`, `plots`) should always list only what the problem needs:
each grading run starts a fresh Julia, and loading Flux and MLJ together
costs tens of seconds.

### What the grader measures

Correctness: the learner's function and the reference run on every case;
results compare with `isequal` (or `isapprox`, applied element by element
through tuples, pairs and arrays of non-numbers; an array of numbers is
compared as a whole, `norm(a - b) <= rtol * max(norm(a), norm(b))`, so a
near-zero entry next to large ones does not need its own tolerance; a scalar
near zero does), result types must match when
`check_type` is true (`3` vs `3.0` is a real bug in Julia), and when the
reference throws, the learner must throw the same exception type.

Performance (only when every case passes), measured in the same process as the
reference and interleaved with it, so verdicts are ratios, not machine speed:

| verdict      | meaning |
|--------------|---------|
| `fast`       | at most 1.75× the reference's time at the largest size |
| `slow`       | more than 5× the reference's time |
| `allocates`  | allocates more than the reference (beyond 256 B or half the reference) |
| `scaling`    | growth exponent ≥ 0.5 above the reference's (needs two sizes) and > 2× slower |
| `unstable`   | a local variable with an abstract inferred type that no function of the reference also has (in the entry function, or in any function the submission defines, in every specialization compiled while grading), or a non-concrete return type where the reference's is concrete |

Inference is inspected unoptimised, for the entry function at the `perf`
argument types and for every other function the submission defines
(helpers, keyword-argument bodies) at each argument type it was compiled for
during grading, inlined or not; the feedback names the helper
(`` `s::Union{Float64, Int64}` in `total` ``). Instability is relative: a
local type string that the reference also has somewhere is not reported.
Locals that hold a type (`T = eltype(v)`) count as concrete. If measuring fails
(an error at the perf sizes, bad `perf.args`), the learner is told
"Performance could not be measured" with the error, and no timing verdict
is given, so the reference self-test fails loudly.

### Variants

Variants are solutions with the verdicts the grader must give them; `tutor
course verify` checks each one. Every problem needs at least one `incorrect`
variant, and a problem with a `perf` section should demonstrate its point with
performance variants: an allocating version (`["correct", "allocates"]`), a
type-unstable one (`["correct", "unstable"]`), a quadratic one with two sizes
(`["correct", "scaling"]` or `["correct", "slow"]`), an alternative idiomatic
solution (`["correct", "fast"]`). Only list verdicts with a wide margin:
timing verdicts must hold on a busy CI machine. The reference is checked to
be `correct` against itself (and `fast`, when there is a `perf` section),
and the starter must not pass. Every problem should have a `perf` section:
without one the learner gets no performance feedback at all.

### Find the bug

**Learning purpose.** Reading and debugging numerical code is a different skill
from writing it: the learner gets a plausible solver with one planted error
(a wrong stage time, an off-by-one grid spacing, a sign in an adjoint) and has
to localize it from *measurements*, the way a working scientist does, rather
than by comparing with a known answer. The convergence tests are the evidence;
the hints fade in only after the learner has read what the tests measure.

A find-the-bug problem is an ordinary practice problem with a `[problem.bug]`
table and **no `starter`**: the starter is generated from the reference.

```toml
  [problem.bug]
  kc = "convergence-order"                       # one of the unit's KCs
  find = "k2 = f(t + h / 2, y + h / 2 * k1)"     # occurs exactly once in the reference
  replace = "k2 = f(t, y + h / 2 * k1)"          # the planted error: changes exactly one line
  answer_tokens = ["t + h / 2"]                  # pieces of the fix (in `find`, not in `replace`)
  misconception = '''What belief the planted line models; shown once fixed.'''

  [[problem.bug.test]]
  name = "observed order on y' = -y + cos t (f depends on t)"
  # expect: derive the range here (error model, measured fit, rounding floor, what a wrong method measures)
  code = '''Julia that calls the entry and prints one line'''
  row = '^observed order: (?<m>\S+)$'            # a named group `m`: the measured number
  expect = [3.7, 4.3]                            # inclusive
  explain = '''What the measurement means when it fails; never where the error is.'''
```

Rules, checked by `Course.validate_course` (structure; the test suite runs it)
and `tutor course verify` (measurements):

* `find` occurs exactly once in the reference, and replacing it changes
  exactly one line: one error, one line to fix. A hand-written `starter` is
  refused, so the planted code can never drift from the reference.
* Every test passes on the reference and **at least one fails on the planted
  starter** (verify runs them, each in a fresh process). Prefer a set where
  one test passes on the bug and another fails: the contrast is the hint
  (unit 31: order 4 on `y' = -y`, order 1 on `y' = -y + cos t`, so the error
  is where `t` enters).
* Level-1 feedback is the tests' names and explanations, then `hints[1]`:
  none of them may contain an `answer_tokens` entry. Later hints may be more
  specific. The tests' code is visible to the learner (it is the
  specification), so it may show the correct formula; that is fine, as long
  as the prose does not point at the line.
* Derive each `expect` range in a comment next to it (invariant 9), and pick
  problem sizes whose smallest error stays well above rounding, or the fitted
  order bends.
* The usual problem rules hold: cases, `rtol` derived, at least one
  `incorrect` variant (a *different* wrong solver, not the planted one: the
  starter is already graded), and a correct variant in another style.

The site runs the tests through `tutor serve` (a learner without it gets the
hints at once, since there is nothing to measure). A problem counts as fixed
when the grader and every test pass on the same code; then the planted line,
the reference's line and the misconception are shown. On the command line,
`tutor practice <id> file.jl` prints the test table, and `--hints=N` shows the
first N hints.

### Parsons problems

A Parsons problem gives the lines of a kernel shuffled, plus a few wrong
lines, and asks for a working order. It sits between reading a worked example
and writing the code: the learner makes the decisions that matter (which
update waits for which value, what starts the accumulator, which loop is
inside which) without typing syntax. Pick kernels where the *order* is the
concept: Kahan's correction must be measured before `s` is overwritten; a
stage needs the previous stage's slope.

```toml
[[problem]]
id = "fp-kahan-parsons"
entry = "kahan_sum"
reference = '''
function kahan_sum(x)      # head = 1: fixed
    s = 0.0                # the movable lines, in a working order
    ...
    end
    return s               # tail = 2: fixed
end
'''
cases = ["fill(0.1, 10)", "..."]
compare = "isequal"

  [problem.parsons]
  kc = "floating-point-rounding"
  head = 1
  tail = 2

  [[problem.parsons.distractor]]
  line = "        c = t - (s + y)"    # indented like the line it can replace
  replaces = 6                         # 1-based, among the movable lines
  misconception = "..."
```

**Which orders work is measured, not typed.** `tutor course record` runs every
arrangement in one fresh process in the unit's env: one of each line or its
distractor, every order, with equal texts (two `end` lines) tried once.
Indentation is part of each line and must match the block structure (4 spaces
per level, read by `Course.parsons_depth`), so most orders are rejected before
they are parsed; the rest are parsed, and those that parse are run
(interpreted, each in a new module) on the problem's cases and compared with
the reference as the grader would. The working orders are stored under
`parsons` in the unit's outputs file. `verify` re-runs the enumeration and
fails when the set changes, when the reference's own order is not in it, or
when any working order contains a distractor (then it is not a mistake).

The rules (`Course.parsons_problems`):

* The starter is generated (the fixed lines with a gap); remove `starter`.
* 3 to 8 movable lines, at most 3 distractors; no blank lines, no tabs, no
  movable `while` (an order could loop forever). The head must open the
  function.
* Each distractor has a misconception, replaces a different line, and is
  indented like that line, so indentation alone does not give it away.
* `compare` is `isequal` or `isapprox`, with at least two explicit cases and
  no `gen`; every order runs on those cases only.
* The usual problem rules hold too (an `incorrect` variant, a correct one in
  another style): the grader still grades a whole file.

Feedback is the same on the site and the command line
(`Course.parsons_feedback`, `web/src/parsons.ts`): a distractor shows its
misconception; a wrong number of lines says how many; otherwise the longest
prefix that starts some working order. More than one order may work (two
initialisations that do not depend on each other); the feedback says how many
were measured. Hints open after the first check. The site needs no server to
check an order; once it works, `tutor serve` can grade the whole program. On
the command line, `tutor practice <id>` lists the lines with letters and
`--order=c,e,a,...` checks an order.

Measured on Windows (plain processes, 2026-11-13): the three course problems'
enumerations take 2.5 to 7.4 s each.

## Style

* Teach one idea per section; show it, then say what to notice in the output.
* Say where Julia differs from Python, MATLAB or R when that is the likely
  misconception (1-based indexing, column-major arrays, `/` vs `÷`, integer
  overflow, copying slices).
* Do not claim anything the examples do not show. If a claim depends on
  the Julia version, it is about 1.10 (the pinned release).
* Hints never contain the answer; the first one names the idea, the second
  gets more specific.
