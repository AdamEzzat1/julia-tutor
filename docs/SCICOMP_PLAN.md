# Plan: a Scientific computing track (2026-11-09)

Status: approved for drafting. Nothing below is recorded in the container
yet; every example is recorded and verified there before it ships.

## Why, and what it adds

Julia's core use is numerical simulation and optimization: climate and
ocean models, pharmacometrics, circuits and power systems, economics,
operations research. The course so far teaches the tools (unit 24 solves
ODEs, unit 25 calls Optim and JuMP, units 14 and 18 cover single-core
performance and threads) but not the ideas that decide whether a result can
be trusted: conditioning and stability, what a solver's error estimate is,
which linear solver to use and why, how to model a physical system or an
optimization problem well, and what limits parallel speedup.

Each unit therefore has a conceptual core shown by one "see it happen"
example, then the Julia way to do it, then graded problems where the learner
implements the idea (Kahan summation, an embedded-pair step controller, CG,
a KKT check, a tight big-M).

## Place in the course

New track `scicomp` ("Scientific computing") after `ecosystem` and before
`sciml`. Scientific ML builds on numerical methods, so:

* `TRACK_REQUIRES`: `scicomp` assumes foundations, core, advanced, ecosystem;
  `sciml` assumes those and `scicomp`.
* The two numerical-methods drafts written for SciML (PDE discretization,
  stiffness) move into `scicomp`. The SciML track keeps sensitivities,
  adjoints and neural ODEs, UDEs, SINDy, PINNs, PINN limits.
* Renumbering (all drafts are uncommitted; done once both drafters finish):
  scicomp 30-42, sciml 43-48. Ids, file names, `prerequisites`, output files
  and "unit NN" prose references are updated by one script; every unit is
  re-recorded in the container anyway.

## Units

| # | Unit | Builds on | Conceptual core and the example that shows it | Graded problems |
|---|---|---|---|---|
| 30 | Floating point, conditioning and stability | 02, 14, 23 | forward error ≤ condition number × backward error; cancellation is exact (Sterbenz) yet can expose earlier error; `(1-cos x)/x²` vs `2sin²(x/2)/x²`; a backward-stable LU on a Hilbert matrix still gives a wrong x, because the problem is ill-conditioned | Kahan summation vs a BigFloat reference; a stable `log1pexp`; predict digits lost from κ |
| 31 | Convergence order and error control | 24, 30 | observed order from log-log slopes, Richardson extrapolation; an adaptive solver's error estimate is the gap between two embedded methods, a local estimate scaled by `abstol + reltol·|u|`; a work-precision sweep shows global error 1-2 digits worse than `reltol` | order from (h, error) pairs; Richardson for a derivative; an Euler/Heun embedded-pair step accept/reject controller |
| 32 | Dense linear algebra in practice | 14, 20, 30 | what `\` does for each matrix type; never `inv(A)*b`; normal equations square κ, so QR beats them on a Vandermonde fit; factor once, solve many | least squares via QR; reuse a factorization in a loop (graded on allocations); detect numerical rank with the SVD |
| 33 | Sparse matrices and iterative solvers | 32 | CSC storage, fill-in, reordering; CG and GMRES converge at a rate set by the spectrum; on 2D Poisson the CG iteration count grows with the grid, and a preconditioner flattens it; LinearSolve.jl as one interface | sparse 2D Laplacian with `kron`; hand-written CG (graded on the residual); Jacobi preconditioner |
| 34 | PDEs as ODE systems (moved from SciML) | 24, 30, 33 | method of lines, residuals, the Laplacian's spectrum | as drafted |
| 35 | Stiffness and stability (moved from SciML) | 23, 24, 34 | stability, not accuracy, sets an explicit step | as drafted |
| 36 | DAEs and acausal modelling | 23, 24, 35 | differential index, consistent initial conditions, mass-matrix form; the Cartesian pendulum is index 3, drifts off the constraint until the index is reduced (by hand: differentiate the constraint); acausal components with ModelingToolkit and `mtkcompile` | index of small systems; a consistent initial condition; an RC circuit vs its exact solution |
| 37 | Stochastic and delay equations, ensembles, uncertainty | 24, 27, 31 | Euler-Maruyama has strong order 0.5 and weak order 1: on geometric Brownian motion with a fixed path, halving dt barely helps one path while the mean converges; Monte Carlo error ∝ 1/√N; DDEs by the method of steps | Euler-Maruyama with a given RNG; a Monte Carlo confidence interval; a DDE by method of steps vs its exact solution |
| 38 | Constrained nonlinear optimization | 25, 32 | Lagrangian, KKT conditions, complementarity, barrier methods; Ipopt is local: one nonconvex JuMP model from two starts gives two answers both reported `LOCALLY_SOLVED`; duals as sensitivities, checked by perturbing the constraint | KKT residuals at a point; a 1D log-barrier method; multipliers of an equality-constrained QP |
| 39 | Modelling discipline in JuMP: integer programs | 25, 38 | LP relaxation strength, big-M sizing, indicator constraints, linearizing products; facility location with M = 1e6 vs a tight M (root bound, node count), and an M too small silently cutting off the optimum | tightest valid M from bounds; linearize a product of binaries; an either-or constraint (graded on the optimum) |
| 40 | Parallel computing and its limits | 14, 18 | SIMD and data layout, memory bandwidth and the roofline, false sharing, threads vs Distributed, Amdahl vs Gustafson; a bandwidth-bound triad barely speeds up on 2 threads while a compute-bound kernel nearly doubles; KernelAbstractions on the CPU as a model of GPU kernels | a SIMD-friendly reduction (time, allocations); a race-free per-thread reduction; Amdahl/Gustafson from given fractions |
| 41 | Case study: a pharmacokinetic model | 24, 31, 35, 37, 38 | two-compartment model with dosing callbacks, a stiff absorption phase, a parameter fit to simulated concentrations, an ensemble over patient variability | dose callback schedule; AUC by quadrature of the solution; fitted clearance within a stated tolerance |
| 42 | Case study: a circuit and an energy dispatch market | 36, 38, 39 | an acausal circuit model; a dispatch LP whose dual prices are marginal costs, the economics reading of duality | node equations of a small circuit; merit-order dispatch; read a price from a dual |

## Honest-teaching points (each with a source in its unit)

Global ODE error has no cheap guarantee; big-M heuristics can fail; choosing
a preconditioner is problem-specific; Itô vs Stratonovich is a modelling
choice; Amdahl and Gustafson answer different questions; speed on a shared
2-thread sandbox is noisy, so speed is graded by ratio to a reference.

## Packages

* New env `scicomp`: LinearSolve, Krylov, IncompleteLU, SparseArrays,
  OrdinaryDiffEq 7, StochasticDiffEq, DelayDiffEq, ForwardDiff, JuMP,
  HiGHS, Ipopt, OhMyThreads, KernelAbstractions, BenchmarkTools, StableRNGs.
  (The existing `diffeq` env stays as it is; mixing OrdinaryDiffEq 6 and 7
  in one env cannot resolve.)
* New env `mtk` for unit 36 (and 42's circuit): ModelingToolkitBase,
  ModelingToolkitStandardLibrary, OrdinaryDiffEq. It is the heaviest stack,
  so it stays apart.
* **Licensing.** ModelingToolkit v11 moved automatic index reduction and
  advanced tearing into AGPL packages; `ModelingToolkitBase` is MIT. The plan
  uses the MIT part only and teaches index reduction by hand, which is also
  the better lesson. Using full ModelingToolkit later is a licensing decision
  for the project owner.
* No PK datasets: data are simulated from known parameters (no open Julia
  replacement for Pumas; the classic datasets ship with R).
* Unverified until measured in the container: load times, memory, whether
  `Distributed.addprocs` works in the sandbox (loopback only).

## Reproducibility rules

Thread reductions and BLAS change summation order: compare with a stated
tolerance, `BLAS.set_num_threads(1)` where exact output is shown. Never
assert Ipopt or Krylov iteration counts or ODE step counts in checked output;
assert status, objective, residual norm, or the solution at fixed times.
Index ModelingToolkit solutions symbolically (`sol[x]`). Timings are
`check = false`.

## Order of work

1. Both SciML drafters finish; renumber and move 30/31 into `scicomp`.
2. Resolve `scicomp` and `mtk` envs (short depot on this host), add Dockerfile
   layers, measure load and first-call times.
3. Track code: `scicomp` in `TRACKS`, `TRACK_REQUIRES`, site labels.
4. Draft units 30-33 and 36-42, two drafters at a time, run on this host.
5. Review every unit; record and verify in the container (CI or local Docker
   after a reboot); then commit and publish.

## Sources

MIT 18.335 (OCW, https://ocw.mit.edu/courses/18-335j-introduction-to-numerical-methods-spring-2019/),
SciML book (https://book.sciml.ai/), ModelingToolkit course
(https://docs.sciml.ai/ModelingToolkitCourse/dev/lectures/lecture1),
ModelingToolkit v11 notes (https://sciml.ai/news/2026/07/27/ModelingToolkitv11/index.html),
DiffEq SDE tutorial (https://docs.sciml.ai/DiffEqDocs/dev/tutorials/sde_example/),
JuMP tips and tricks (https://jump.dev/JuMP.jl/stable/tutorials/linear/tips_and_tricks/),
Krylov.jl preconditioners (https://juliasmoothoptimizers.github.io/Krylov.jl/dev/preconditioners/),
ENCCS Julia for HPC (https://enccs.github.io/julia-for-hpc/),
Kahan on cancellation (https://people.eecs.berkeley.edu/~wkahan/triangle.abs).
Goldberg, Trefethen & Bau, Higham and Williams are cited from memory by the
research pass and are checked before they appear in a unit.
