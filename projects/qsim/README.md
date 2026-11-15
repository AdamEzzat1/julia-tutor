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

## Cross-checks against Qiskit and Yao (`crosscheck/`)

Author-side only: the CI job `qsim-crosscheck` runs both on every pull
request; no learner installs either, and the course runs without them.

* `qiskit_diff.py` (Qiskit 2.5.2, numpy 2.2.6, `requirements.txt`), ported
  from the original: 500 seeded random circuits over the full gate set,
  amplitude for amplitude with global phase; the nine lesson circuits; the QFT
  circuit's unitary vs Qiskit's `QFTGate` (n = 1..6); QPE vs Qiskit's
  `phase_estimation` (which bit-reverses its readout, undone explicitly and
  shown to matter) and vs a textbook QPE built from `QFTGate`†; lesson 8's
  noisy density matrix vs `qiskit.quantum_info.Kraus`. Tolerance 1e-10.
  Unlike the original, a missing input is a failure, never a skipped section.
* `yao_diff.jl` (Yao 0.9.3, the pinned env in `yao/`): the same random-circuit
  distribution and the lesson circuits against a second simulator, in Julia.
  Yao's circuit is built from Yao's own gate blocks by a separate tokenizer,
  never from a QSim matrix.
* `export.jl` rebuilds every lesson circuit from the current reference and
  fails if one differs from the original's export (`lesson_circuits/`), so
  the circuits compared are the ones the course teaches.
* `mutant_layers.py` re-measures which external layer catches each seeded
  mutant (slow; not in CI).

```bash
JULIA="julia +1.10.13" python projects/qsim/crosscheck/qiskit_diff.py
julia +1.10.13 --project=projects/qsim/crosscheck/yao projects/qsim/crosscheck/yao_diff.jl
JULIA="julia +1.10.13" python projects/qsim/crosscheck/mutant_layers.py
```

Measured on 1.10.13 (2026-11-15, `mutant_layers.py`, 100 random circuits per
layer). FAIL: a comparison caught it; drift: only the "rebuilt lesson circuits
equal `lesson_circuits/`" guard did; pass: the layer missed it. The unit tests
(`holemap.toml [seeded]`) catch all 22.

| mutant | qiskit | yao |
|---|---|---|
| H-sign, S-conj, T-angle, SX-dagger, RX-halfangle, RY-sign, RZ-sign, U-phase, CX-endian, CP-sign, CCX-control, apply-endian | FAIL | FAIL |
| kraus-transpose | FAIL | pass |
| QFT-angle, QFT-noswap, iQFT-sign, QPE-power | FAIL | drift |
| Grover-nodiff | drift | drift |
| sampler-bias, measure-flip, ptrace-conj, bloch-y | pass | pass |

How to read it:

* A simulator-vs-simulator diff cannot see a wrong circuit *builder*: both
  simulators run the same (wrong) gate list and agree. Only a comparison with
  an independent algorithm catches that (Qiskit's `QFTGate` and
  `phase_estimation`), or the drift guard, which only says the circuit
  changed, not that it is wrong. So Yao reports the QFT and QPE mutants as
  drift only, and Grover-nodiff (Qiskit has no library Grover in this diff)
  is drift in both.
* Yao has no noise check, so kraus-transpose passes there.
* Neither diff looks at sampling, measurement, partial trace or Bloch vectors;
  those four are caught by the unit tests alone.

## Not here yet

* `apply!` allocates (an offset table and a buffer per call; see
  `measure_baseline.toml`). CLAUDE.md's M9 definition of done asks for
  zero-allocation kernels; that is not met by this port.
