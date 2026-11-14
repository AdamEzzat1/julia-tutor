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

## Style

* Teach one idea per section; show it, then say what to notice in the output.
* Say where Julia differs from Python, MATLAB or R when that is the likely
  misconception (1-based indexing, column-major arrays, `/` vs `÷`, integer
  overflow, copying slices).
* Do not claim anything the examples do not show. If a claim depends on
  the Julia version, it is about 1.10 (the pinned release).
* Hints never contain the answer; the first one names the idea, the second
  gets more specific.
