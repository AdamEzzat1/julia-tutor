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

## Style

* Teach one idea per section; show it, then say what to notice in the output.
* Say where Julia differs from Python, MATLAB or R when that is the likely
  misconception (1-based indexing, column-major arrays, `/` vs `÷`, integer
  overflow, copying slices).
* Do not claim anything the examples do not show. If a claim depends on
  the Julia version, it is about 1.10 (the pinned release).
* Hints never contain the answer; the first one names the idea, the second
  gets more specific.
