# julia-tutor: design decisions

Status: written in the vertical-slice session (2026-11-08), pinned to Julia
1.10.13 (LTS). Each section ends with the decision. Claims that rest on a
measurement name the measurement; claims I could not verify are marked
**unverified**.

## 1. Projects

The audience is scientists and people building reasoning systems, so the
projects are a computer-algebra core, numerical solvers and inference engines,
not order systems.

| # | Project | Family | Why Julia | Correctness criterion | Determinism |
|---|---|---|---|---|---|
| 1 | **symdiff**: symbolic differentiation + canonical simplifier + term rewriting with a termination measure (built) | Symbolic AI | Multiple dispatch for per-node rules (`deriv(::Mul)`, `dfn(::typeof(sin), u)`), parametric `Fn{F}`, `Expr` → term via a macro | Exact rational evaluation against known derivatives; idempotence and order-independence over an exhaustive small-term enumeration; soundness of rules on known cases; `is_size_decreasing` proves termination | Exact arithmetic, no RNG |
| 2 | **odeint**: adaptive Dormand–Prince 5(4) with step control and dense output | Scientific | Generic over number types (Float64, BigFloat, dual numbers) without code changes; zero-allocation inner loop is measurable | Fitted convergence order of the fixed-step method (slope 5 ± 0.15 in the asymptotic regime); global error proportional to tolerance; energy drift on Kepler grows linearly (non-symplectic), not exponentially; exact solutions for linear systems | No RNG; tolerances derived from the method's error constant |
| 3 | **datalog**: Datalog with semi-naive evaluation and stratified negation | Symbolic AI | Dispatch on literal kinds, `Set{Tuple}` relations, a macro for rules | Naive and semi-naive evaluation give the same model; transitive closure on known graphs; unstratifiable programs rejected | Relations are sets; output sorted |
| 4 | **fvsolve**: finite-volume advection/heat in 1-D/2-D with flux limiters | Scientific | Column-major loops, `@views`, broadcast fusion; allocation counts matter | Mass conserved to `n·eps·|mass|`; 2nd-order convergence on smooth data, 1st near shocks; TVD property of the limiter; CFL violations detected | No RNG |
| 5 | **mcmc**: Metropolis–Hastings and HMC on known targets | Scientific / statistical | Generic log-densities, multiple dispatch on proposal kinds | Fixed-seed reproducibility of the whole chain; posterior means within k·MCSE (ESS-based) with a stated flake probability; detailed balance on a discrete target, checked exactly | Needs a version-stable RNG: StableRNGs.jl earns its place here |

Other candidates considered: a STRIPS/PDDL-lite planner with A* (good for
admissibility proofs, overlaps with datalog for search), a DPLL SAT solver
(excellent tests, little that is Julia-specific), N-body with a symplectic
integrator (good conservation tests; folded into odeint as a later stage).

**Order: symdiff, then odeint.** symdiff first because its correctness is exact
(no tolerance authoring on day one), it teaches the core language ideas
(dispatch, parametric types, `Expr`, immutability, `==`/`hash`), and its
termination and soundness questions are real symbolic-AI content. odeint second
because it is the cleanest early test of numerical honesty.

**Bridge (symbolic Jacobian → implicit/Rosenbrock solver, checked against
finite differences): worth it, but as a later capstone, not as a coupling between
projects 1 and 2.** If odeint depended on symdiff, a student stuck in one would
be blocked in the other, and every symdiff change would invalidate odeint's
starter and holemap. As a capstone it uses both *reference* solutions through a
narrow interface (`to_expr(t)` → compiled function). That also teaches world age
(`eval` then `invokelatest`). The finite-difference comparison is itself a
numerical lesson: the central-difference error is ~h²·|f'''| + eps/h, minimised
near h = cbrt(eps), so the tolerance is derived, not tuned.

## 2. What Julia already gives us, and the gap left for the tutor

Use directly (measured facts, not rules):

| Tool | Gives | Used in slice | Cost / instability |
|---|---|---|---|
| `Test` (`@testset`, `@test`, `@test_throws`, `@inferred`, `detect_ambiguities`) | behaviour, inferred-type equality, ambiguities | yes | `Test` internals used by `src/child/run_tests.jl` (`DefaultTestSet.results`, `Fail`/`Error` fields) are not public API; re-verified on every upgrade |
| `--check-bounds=yes` in every test run | turns `@inbounds` misuse into a `BoundsError` (a measurement) | yes | none |
| `Base.return_types`, `@code_warntype` | the compiler's own inference result | yes (`measure.jl`) | output format of `@code_warntype` changes between releases; `return_types` is stable enough |
| `@allocated` / `Base.@allocations` after warm-up | allocation counts excluding compilation | yes | counts can change with compiler versions → baseline regenerated per upgrade |
| JET.jl `report_opt` / `report_call` | runtime dispatch, likely MethodErrors, via abstract interpretation | optional in `measure.jl` (JET 0.9.14) | **each JET minor supports specific Julia minors** (0.9.x ↔ 1.10 here); it reaches into `Core.Compiler`; on failure explain prints "unavailable" instead of guessing |
| AllocCheck.jl | static proof that a call allocates nothing (LLVM-level) | not yet | compiler-internal; use only in the performance-focused stages of odeint/fvsolve |
| Aqua.jl | type piracy, ambiguities, unbound type params, stale deps | not yet | piracy is detected from method tables, which beats any syntactic rule; add when the first project defines methods on foreign types |
| ExplicitImports.jl | implicit/stale imports | no | style-level for novices; low value |
| `--depwarn=error` | deprecations as errors | planned | harmless on a pinned release |

**The gap the tutor fills** is not detecting problems the compiler can measure.
It is three things:
1. **Explaining the cause in the learner's terms, at the cause's location.** JET
   reports "runtime dispatch in `area(::Shape)`"; the cause is `x::Real` in a
   struct three files away. A rule points at the declaration, and a measurement
   confirms or refutes the cost.
2. **Patterns that are not errors to any tool:** `[]` (Vector{Any}), abstract
   field types, the `!` convention, `1:length(x)`, float `==` in tests,
   column-major loop order, `@threads` reduction races, `x == missing`, unseeded
   RNG in tests, byte-indexing strings with arithmetic indices.
3. **Pedagogy:** knowledge components, fading, hint levels and misconception
   tracking. None of the tools has a model of the learner.

### Corrections and refinements to the proposed misconception list

* **Type-unstable returns** are not a static rule. They are measured
  (`@inferred`, `return_types`, JET). A rule may only point at a likely cause.
* **Closures capturing a reassigned variable (`Core.Box`)**: the static
  pattern (assigned after capture, or inside the closure) is detectable, but
  whether lowering actually boxes is a compiler decision. Rule points, and
  `@code_warntype`/JET confirms.
* **Method ambiguities**: `Test.detect_ambiguities` (used in symdiff's tests)
  and Aqua, not a rule.
* **Type piracy**: Aqua (method-table based). Syntax can only catch the
  blatant `Base.:+(::Int, ::Int)` case.
* **`@inbounds` without a bounds argument**: the rule points; the measurement is
  `--check-bounds=yes` in the test run.
* **Row-major loop order**: the cost cannot be measured deterministically
  (it is cache timing, and the checker and tests may not use clocks). It stays an
  ADVICE rule with an optional, clearly labelled, non-graded benchmark.
* **Data races in `@threads` reductions**: the static pattern (`s += ...` on an
  outer variable inside `@threads`) is reliable; a multi-threaded run can show a
  wrong result but **cannot prove absence of a race**. Graded runs stay
  single-threaded; a separate, labelled nondeterministic probe may run with 4
  threads.
* **Unseeded `rand()` / global RNG**: the deeper problem is that *seeded*
  `Random.default_rng()` and `Xoshiro(seed)` streams are **not guaranteed stable
  across Julia minor releases** (the Random docs say so). Tests must pass an RNG
  explicitly, and the generator must be version-stable (StableRNGs.jl in mcmc).
* **`nothing` vs `missing`**: mostly semantic, but `x == missing` (returns
  `missing`, so an `if` throws `TypeError`) is a statically visible bug and a
  good rule.
* **Additions** the list lacked: annotating arguments "for speed"
  (`f(x::Float64)` doesn't make code faster and kills genericity); `==` on structs
  with `Vector` fields being `===` (symdiff defines `==` *and* `hash`, and a
  rule for "`==` without `hash`" is planned); `const` redefinition (behaviour
  changed in 1.12, so it must be version-pinned in lessons); `Vector{Vector}`
  fields; `push!` in a hot loop versus preallocation (measured by allocations).

### Habits from other languages

| Habit | Python | R | MATLAB | In Julia |
|---|---|---|---|---|
| Mutable default argument shared across calls | bug | – | – | **does not exist**: default expressions are evaluated on every call |
| `b = a` copies | no (binds) | yes (copy-on-modify) | yes (copy-on-assign) | binds; R/MATLAB intuition is wrong, Python intuition transfers |
| Slices are views | yes (NumPy) | no | no | **copies**; NumPy intuition is wrong (use `@view`/`@views`) |
| Memory order | row-major (NumPy default) | column-major | column-major | column-major; NumPy/C loop order is wrong |
| Indexing base | 0 | 1 | 1 | 1 (but generic code uses `eachindex`/`axes`) |
| Integer overflow | arbitrary precision | NA + warning | saturates | **wraps silently** (`typemax(Int) + 1 < 0`) |
| Vectorise for speed | yes | yes | yes | unnecessary; loops are fast; vectorised code allocates temporaries unless fused with `.=` |
| `None` / `NA` | `None` ≈ `nothing` | `NA` ≈ `missing` | `NaN` | `nothing` (absence) vs `missing` (unknown, propagates) |
| Methods live in classes | yes | S4/R5 partly | classdef | functions with methods on types; no `obj.method()` |
| Top-level script code is fine | yes | yes | yes | works, but non-const globals defeat specialisation; soft scope differs between REPL and files |

## 3. What to build the checker on

| Option | Sees | Cannot see | Cost |
|---|---|---|---|
| **JuliaSyntax.jl (chosen)** | Lossless tree with byte positions and trivia; exactly Julia's surface syntax, macros *unexpanded* (good: findings point at what the student wrote) | Types; which method a call dispatches to (that is a runtime fact); what a macro expands to; the body a `@generated` function will produce; contents of string macros (`r"..."`) | Low. The package (1.0.2) is the same parser family Base 1.10 uses by default; a test checks that both produce identical `Expr`s on our corpus, since Base bundles its own copy |
| Scope resolution: **hand-written resolver (chosen)** | Params, assignments, loop and comprehension vars, `local`/`global`, catch vars | Precise nested-scope rules (we merge nested scopes, which over-approximates locals, so we can miss but not invent findings); macro-introduced bindings | Small, owned, testable |
| JuliaLowering.jl | Real scope resolution and macro expansion with provenance back to source | – | **Experimental**, API moving, targets newer Julia than 1.10; revisit at the upgrade milestone |
| JET.jl | Real types via the compiler's abstract interpretation, given an entry signature | Code not reachable from the analysed signature; anything with abstract argument types is imprecise (many "may" reports) | Tied to `Core.Compiler` internals and to specific Julia minor versions (JET 0.9.x on 1.10). Used as an optional *measurement*, never as a rule's premise |
| StaticLint.jl | Scope, some type hints (LanguageServer stack) | as above | Uses CSTParser, not Base's parser (divergence risk on new syntax); slowed maintenance |
| Rust + hand-written Julia parser | whatever we build | – | Very high: juxtaposition (`2x`), contextual keywords, `begin`/`end` inside indexing, string macros, Unicode operator precedence, `where` and `do` syntax. It would diverge from Julia's parser. The Rust tutor's choice does not transfer |

Multiple dispatch makes "what does this call do" a runtime question. Rules
therefore avoid premises about callees (JT003 sees writes into parameters and
calls to `!` functions; it does not follow into non-`!` helpers, and says so in
its false-positive note).

**Decision:** checker in Julia on JuliaSyntax.jl 1.0.2, a hand-written scope
resolver, and JET only as a measurement in `explain`.

## 4. Sandboxing and latency

Julia code can `ccall` any C function, `run` processes, `Libdl.dlopen` libraries,
`Pkg.add` (network), `download`, and `eval`/`include_string` code built at run
time. A static ban is trivially bypassed: `eval(Expr(:call, Symbol("r","un"), ...))`
never contains `run` as an identifier, and `@eval` can construct a `ccall`.
**Containment must come from the OS.**

Plan (milestone M3):
* **Linux:** bubblewrap (or nsjail): new network namespace (no network),
  read-only bind of the Julia install and a pre-instantiated depot, a tmpfs
  working directory, `--die-with-parent`, cgroup limits on memory, CPU time and
  pids (Julia reserves a large virtual address space, so `RLIMIT_AS` is the wrong
  tool), and seccomp to deny `execve` after start.
  Precompilation spawns Julia subprocesses, so precompile trusted code (Test,
  the reference deps) in a trusted step into the read-only depot, and give the
  sandboxed run a writable *first* depot entry on tmpfs for the student
  package's own cache.
* **macOS / Windows:** run the same image under Docker/Podman with
  `--network=none --read-only --tmpfs /work --pids-limit --memory --cpus
  --security-opt=no-new-privileges`. Native Windows AppContainer/job objects are
  possible but are a project of their own.
* **Escape test suite (M3 definition of done):** each must be contained:
  `ccall(:system, ...)`, `run(`...`)`, `Libdl.dlopen`, `download`, `Pkg.add`,
  an `eval`-constructed `ccall`, writing outside the work dir, reading `~/.ssh`,
  a fork bomb via `run`, `while true end`, a memory bomb, and filling the disk.

**Latency.** Measured on this machine (Windows 11, Julia 1.10.13, nothing else
running, wall clock, 2026-11-08): bare `julia -e 1` ~1 s; `tutor check` on the
reference 3 s; the symdiff reference suite 6.9 s of test time inside a 9 s
process; `tutor test` on the stage-1 starter 15–17 s end to end (tutor process +
child, dominated by compiling SymDiff and its tests); `tutor explain` 109 s, of
which most is the measurement process loading JET and running `report_opt`
(`--no-measure` skips it). `tutor holemap` (22 variants, 4 at a time) ~5.5 min;
`verify_all.sh` ~18 min. Too slow for an edit-test loop at the explain level:
that is what M7 (and making JET opt-in) must fix. Options:
* **fresh process per run (chosen now):** isolation and determinism for free;
  slow.
* **custom sysimage (PackageCompiler) with Test, TOML and the runner child
  baked in:** removes load and compile time of shared code; student code still
  compiles every run. Must be rebuilt (and re-verified) on every Julia upgrade.
  M7, adopted only if it measurably helps.
* **reused worker pool: rejected.** Methods a submission defined stay in the
  method table (a student's `Base.:+(::Int, ::Int)` poisons every later run),
  globals and `const`s persist, modules cannot be unloaded, new methods need
  `invokelatest` because of world age, RNG and `__init__` side effects persist.
  Results would depend on run order, which breaks determinism.
* **fork server: rejected.** Julia's runtime (libuv, threads, GC) is not
  fork-safe.

## 5. What is not stable (anti-hype)

* **Compiler internals:** JET, AllocCheck and Cthulhu track `Core.Compiler`; a
  Julia minor upgrade needs new versions and may change reports.
* **Lowering and scope tooling:** JuliaLowering is experimental. Base's bundled
  JuliaSyntax is internal (we use the package and test agreement).
* **RNG streams:** not guaranteed across minor releases (Xoshiro became the
  default in 1.7; `rand(1:n)` sampling changed before that).
* **Printed output:** type printing (`Array{Any,1}` → `Vector{Any}` in 1.6),
  `MethodError` texts, stack-trace layout, `Expr` printing (`2x`). That is why
  every lesson carries `verified_on` and is re-run on upgrade.
* **Package churn:** SymbolicUtils/Symbolics majors, the Metatheory 2.0
  e-graph rewrite, ModelingToolkit majors, and OrdinaryDiffEq splitting into
  subpackages (2024). This is one reason the reference solutions depend on
  nothing outside the stdlib.
* **`const` redefinition** semantics changed in 1.12 (binding partitions).
* **Latency:** better since package images (1.9), but test runs still compile.

## 6. Authoring cost for numerical lessons and tests

A wrong tolerance is as bad as a wrong answer key: too loose passes wrong
solvers, too tight fails correct ones that round differently. Each numerical
test needs:
1. a derivation (error bound × condition, or the method's error constant and
   convergence order, or a conservation law's rounding bound in units of eps);
2. a check that *different correct implementations* pass (operation order
   changes rounding: run the reference plus at least one alternative style);
3. for convergence-order tests, step sizes inside the asymptotic regime and
   above the round-off floor, a least-squares slope on log–log data, and an
   acceptance band justified by the next term of the error expansion;
4. no BLAS bit-patterns: even with `OPENBLAS_NUM_THREADS=1` the kernels depend
   on the CPU (AVX2 vs AVX-512), so BLAS results always get a tolerance.

Estimate: an exact test takes minutes to write; a defensible numerical test
takes about half a day, including the derivation written into the test file.
The numerical analyst reviews every tolerance before a milestone is done.
Predict-the-output lessons avoid float output except where the point *is*
the float (`0.1 + 0.2`), whose shortest-representation printing has been stable
since 1.0 **(unverified across all releases; re-verified on each upgrade by
`tutor lessons verify`)**.
