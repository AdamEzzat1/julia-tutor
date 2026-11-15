# qsim: a state-vector quantum simulator in plain Julia

The project of the Quantum computing course (`course/courses/quantum.toml`,
units 49-61). LinearAlgebra, Random and Test only, so it runs offline, in the
base env, and with `--sandbox=none`.

## Where it comes from

Adapted from the project owner's own verified simulator ("quantum-julia":
`src/QSim.jl`, nine self-checking lessons, a Qiskit differential test and a
mutation test of 22 injected bugs). What changed in the port:

* The nine lessons' checks are now testsets of `reference/test/runtests.jl`
  (`lesson 1: ...` to `lesson 9: ...`), with the same seeds and the same
  order, so the tutor's runner, holemap and explain see them.
* The circuit builders (QFT, inverse QFT, Grover, Bernstein-Vazirani, QPE)
  moved from the lessons into `reference/src/Algorithms.jl`, so they can be
  holes.
* Tests were added: `basis_state` values and both ends of its range check,
  the all-zeros bit string, and `SX ≈ e^{iπ/4}·RX(π/2)`. In the original
  only the Qiskit diff caught the `SX-dagger` mutant (see the table below);
  now the tests alone kill all 22.
* One measured type instability was fixed: `reduced_density` inferred `Any`
  (the tensor's rank is only known at run time); a `::Matrix` assertion
  restores it (`measure_baseline.toml`, `inferred.partial_trace`).
* `basis_state` and `bitstring_of` have separate testsets, so a failure
  names one hole (the test-to-hole map is per testset).
* Test count: 2,103; the original's README says 1,884 for its
  unit layer.

## Holes and stages

15 holes over 3 fading stages (`holes.toml`): state basics and `apply!` (1),
controlled gates, partial trace, Bloch vectors and measurement (2), noise,
QFT, inverse QFT, Grover and QPE (3). Every hole has trivial bodies named
after a misconception (big-endian indexing, `transpose` for `'`, θ instead of
θ/2, an iQFT that is the QFT again, ...), each of which must fail a test.

One candidate was dropped as an **equivalent mutant**: an inverse QFT that
negates the phases without reversing the gate order is *correct*, because
the DFT matrix is symmetric (QFT† = conj(QFT)) and every QFT gate is real
except CP, with conj(CP(λ)) = CP(-λ). The reason is recorded next to the hole.

## Explain fixtures

`fixtures.toml` holds one realistic bug per hole, each a different
misconception from that hole's trivial bodies (an inclusive range check,
unpadded bit strings, RY copied from RX, a gate's local bit order reversed, a
Toffoli that needs only one control, measurement without collapse, the
forward QFT in phase estimation, ...). `tutor fixtures qsim --check` runs
explain on each and requires its "Start here" to name the buggy hole.

## The 22 seeded mutants (`mutants.toml`)

Ported from the original's `verify/mutation_test.py`. `tutor holemap qsim
--check` runs the reference tests against each one; the measured number of
failing testsets per mutant is in `holemap.toml` under `[seeded]`. For
comparison, the original's report (unit tests / lessons / Qiskit; "pass"
means that layer missed the bug):

| mutant | unit | lessons | qiskit |
|---|---|---|---|
| H-sign, S-conj, T-angle, U-phase, CX-endian, CP-sign, apply-endian, QFT-angle, QFT-noswap | FAIL | FAIL | FAIL |
| SX-dagger | pass | pass | FAIL |
| RX-halfangle, RY-sign, RZ-sign, iQFT-sign, QPE-power, kraus-transpose | pass | FAIL | FAIL |
| CCX-control | FAIL | pass | FAIL |
| sampler-bias, ptrace-conj | FAIL | FAIL | pass |
| measure-flip | FAIL | pass | pass |
| bloch-y, Grover-nodiff | pass | FAIL | pass |

No single layer was enough there; here the lesson checks and the unit tests
are one suite, plus the new SX test.

## Not here yet

* The Qiskit differential test and the Yao 0.9.3 cross-check are author-side
  only and come in a later PR (a pinned CI job and `crosscheck/`).
* `apply!` allocates (an offset table and a buffer per call; see
  `measure_baseline.toml`). CLAUDE.md's M9 definition of done asks for
  zero-allocation kernels; that is not met by this port.
