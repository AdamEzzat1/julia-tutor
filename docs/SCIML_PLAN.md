# Plan: a Scientific ML track (draft for review, 2026-11-09)

Status (2026-11-10): built, with changes from this draft. The track is now the
sixth, after `scicomp` (docs/SCICOMP_PLAN.md), and requires it. Units 30 and
31 below moved into scicomp as 34 and 35; units 32 to 37 shipped as 43 to 48.
Review changed one claim: unit 45 no longer says a UDE extrapolates where a
pure network does not. Over 16 training seeds the UDE won 9, and the
lower-loss model won 13, so the unit reports that experiment instead. The
text below is the original plan, kept for its reasoning.

## Why this track

Julia's strongest niche is scientific computing, and within it scientific
machine learning: models that combine known physics (differential equations)
with learned parts. The SciML organisation (DifferentialEquations,
SciMLSensitivity, DiffEqFlux, NeuralPDE, ModelingToolkit, DataDrivenDiffEq)
has no equally complete counterpart in other languages. General deep
learning, by contrast, is mostly PyTorch/JAX; the track teaches neural
networks only as parts of scientific models.

## Shape

A fifth track, `sciml`, after `ecosystem`. It is a separate part of the
course and states its entry requirement:

* Every unit lists `prerequisites` from the existing course (validated:
  prerequisites must be earlier units).
* New: a track-level requirement, `requires_tracks = {sciml = ["foundations",
  "core", "advanced", "ecosystem"]}` beside `Course.TRACKS`, checked in
  `validate_course`, exported in `sitedata.jl`, and shown on the website
  above the track ("This track assumes the whole course; each unit names the
  units it builds on").
* Each unit opens with a short "What you need from earlier units" section
  that links the exact earlier sections (for example 24's in-place `f!` and
  `remake`, 23's dual numbers, 26's Lux `ps, st`), instead of re-teaching them.

Code changes: `TRACKS` (src/course.jl:27), the track type, label and blurb
(web/src/course.ts:62, 89-100), the "four tracks" text
(web/src/views/Course.tsx:92), the track requirement in validate and site data.

## Units

| # | Unit | Builds on | Key idea | Graded problems (deterministic) |
|---|---|---|---|---|
| 30 | PDEs as ODE systems: discretization and residuals | 07, 14, 24 | the method of lines turns a PDE into an ODE system; a residual measures how far a candidate is from solving it | `laplacian_1d(u, dx)`; heat-equation `f!(du,u,p,t)`; residual of a candidate on a grid |
| 31 | Stiffness and stability | 23, 24, 30 | the step size of an explicit method is set by stability (Jacobian eigenvalues), not accuracy; unit 24 showed *that* Rodas5P wins, this shows *why* | stiffness ratio from `ForwardDiff.jacobian`; largest stable forward-Euler `dt`; one backward-Euler step |
| 32 | Fitting ODE parameters: sensitivities and Optimization.jl | 23, 24, 25 | gradients through a solve; forward sensitivities cost grows with the number of parameters | Lotka–Volterra loss on data; forward-sensitivity right-hand side by hand; gradient vs finite differences |
| 33 | Adjoints and neural ODEs | 26, 32 | reverse mode through a solver; the adjoint's cost does not grow with parameters; a neural network as the whole right-hand side (Lux) | adjoint of N Euler steps by hand, checked against ForwardDiff; neural-ODE right-hand side from given weights |
| 34 | Universal differential equations: missing physics | 33 | keep the physics you know, learn only the missing term; it extrapolates where a pure network does not (if the known part is right) | UDE right-hand side with fixed weights; extrapolation error on a held-out window |
| 35 | Discovering equations: sparse regression (SINDy) | 34 | a library of candidate terms plus sequential thresholded least squares gives a readable model; noisy derivatives dominate the error | library matrix Θ(X); STLSQ by hand; recover the learned UDE term as an equation |
| 36 | Physics-informed neural networks from scratch | 23, 26, 30, 33 | the PDE residual at collocation points is the loss; spatial derivatives by nested AD; always beside a classical solve of the same problem | PINN loss of a given u(x,t) on fixed points; residual of a tiny fixed-weight network; weighted loss terms |
| 37 | When PINNs fail, and honest comparisons | 36 | the difficulty is optimization (loss imbalance, spectral bias, causality), not network size; with strong baselines classical solvers usually win (Grossmann et al. 2024; McGreivy & Hakim 2024) | gradient-norm ratio between loss terms; causal weights; read a timing/error table and pick the Pareto-better method |

Possible later units, after measuring their cost: 38 Bayesian inverse
problems (Turing over an ODE; builds on 27), 39 ModelingToolkit
(symbolic-numeric modelling; its API changed heavily in v10/v11).

Concept-question material (misconceptions, each with a source): "a bigger
network fixes a failing PINN"; "the training loss is small, so the error is
small" (between collocation points); "an explicit solver on a stiff problem
is merely inaccurate" (it is slow); "reverse mode is always cheaper"
(depends on parameters vs outputs); "a UDE always extrapolates" (only if the
known physics is right); "a trained PINN is a reusable surrogate" (it solves
one instance).

## Packages: one new env, `sciml`

OrdinaryDiffEq, SciMLSensitivity, Lux, ComponentArrays, Optimization,
OptimizationOptimisers, OptimizationOptimJL, ForwardDiff, Zygote,
StableRNGs, DataDrivenDiffEq + DataDrivenSparse (unit 35). All declare
support for Julia 1.10 (checked 2026-11-09).

* **Lux, not Flux**, for networks inside ODEs: SciML recommends it (Flux's
  `restructure` can change precision silently; explicit parameters suit
  solvers). Unit 26 already introduced Lux's `ps, st`.
* **PINNs written by hand** with Lux and ForwardDiff, not NeuralPDE. NeuralPDE
  7 rewrote its parser and switched to Enzyme by default, its stable docs
  predate that, and symbolic discretization plus Enzyme compilation may not
  fit 240 s. Unit 36 points to it as the production tool; adopting it needs
  a measurement first.
* **AD backend and `sensealg` stated explicitly** in every example
  (ForwardDiffSensitivity for small problems, GaussAdjoint with ZygoteVJP
  for the adjoint unit); every gradient cross-checked by a second method.
* Simulated data only; StableRNGs for every random number.

Per the M10 rules in CLAUDE.md, the env PR reports measured Manifest size,
precompile time and load time, measured in the container.

## How outputs are verified

Training results move between CPUs (BLAS/SIMD rounding compounds over
hundreds of Adam steps), so:

* Graded problems use fixed inputs and fixed weights: residuals, right-hand
  sides, hand-written adjoints, STLSQ, loss terms. These grade exactly or
  with a stated `rtol`.
* Training examples print checked facts, not raw losses: "loss fell by more
  than 100×: true", "recovered terms: x*y, y", "max error vs exact: < 1e-2".
  Raw loss curves are figures or `check = false` with a notice saying why.
* Each PINN example sits next to the classical solve and prints both
  accuracy and time.

## Order of work

1. Docker working on this machine (needs the reboot), since recording
   happens in the container.
2. Resolve `course/envs/sciml` in the container; measure size, precompile
   and load; check memory against the 6 GB limit; add the Dockerfile layer.
   Stop and report if a unit's stack does not fit.
3. Track and track-requirement code, tests, website.
4. Units 30 to 37 one at a time, each recorded, verified, checked against
   the length-bias and filler rules, and reviewed on the site before the
   next.

## Sources

SciML book (Rackauckas): https://book.sciml.ai/ ·
missing-physics showcase: https://docs.sciml.ai/Overview/stable/showcase/missing_physics/ ·
neural ODE: https://docs.sciml.ai/DiffEqFlux/stable/examples/neural_ode/ ·
sensitivity choice: https://docs.sciml.ai/SciMLSensitivity/stable/manual/differential_equation_sensitivities/ ·
Lux PINN: https://lux.csail.mit.edu/stable/tutorials/intermediate/4_PINN2DPDE ·
SINDy: Brunton, Proctor & Kutz, PNAS 2016 ·
PINNs: Raissi, Perdikaris & Karniadakis, JCP 2019 ·
failure modes: Krishnapriyan et al., NeurIPS 2021 (arXiv:2109.01050); Wang, Yu & Perdikaris (arXiv:2007.14527) ·
baselines: Grossmann et al. 2024 (arXiv:2302.04107); McGreivy & Hakim 2024 (arXiv:2407.07218).
Some of these were cited from memory by the research pass and are re-checked before they appear in a unit.
