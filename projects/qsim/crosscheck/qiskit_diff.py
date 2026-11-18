"""
Differential test: the qsim reference (Julia) vs Qiskit (Python), two
independent codebases. Ported from the original simulator's verify/qiskit_diff.py.

  A. 500 random circuits over the full gate set -> identical statevectors
     (including global phase: both use the same gate definitions, so a
     phase mismatch would itself be a bug worth seeing).
  B. Every lesson circuit, rebuilt from the current reference by export.jl;
     a rebuilt circuit that differs from lesson_circuits/ is a FAIL of its
     own, and is still compared (lessons.jl).
  C. Algorithm level, against Qiskit's OWN library implementations: the QFT
     circuit's unitary vs QFTGate; the QPE counting distribution vs Qiskit's
     phase_estimation and vs a textbook QPE built from QFTGate^dagger.
  D. Noise: the lesson-8 density matrix vs qiskit.quantum_info Kraus channels.

Every input must exist: a missing file is a FAIL, never a skipped section.
Exit status 0 only if everything agrees to ATOL.

Usage (from the repository root; pins in requirements.txt):
    python projects/qsim/crosscheck/qiskit_diff.py [--n-random 500] [--seed 1234]
JULIA (default "julia") is the Julia command; it is run with
--project=projects/qsim/reference (or QSIM_REFERENCE).
"""
import argparse, glob, os, shlex, subprocess, sys, tempfile
import numpy as np
import qiskit
from qiskit import QuantumCircuit
from qiskit.circuit.library import ZGate, QFTGate, PhaseGate, phase_estimation
from qiskit.quantum_info import Statevector, Operator, DensityMatrix, Kraus

HERE = os.path.dirname(os.path.abspath(__file__))
# QSIM_REFERENCE: another copy of the reference project (a seeded mutant, to
# confirm this diff can fail); default the real one.
REFERENCE = os.environ.get("QSIM_REFERENCE", os.path.join(os.path.dirname(HERE), "reference"))
JULIA = shlex.split(os.environ.get("JULIA", "julia"))
ATOL = 1e-10

ONE_Q = ["id", "x", "y", "z", "h", "s", "sdg", "t", "tdg", "sx"]
ONE_Q_PARAM = {"rx": 1, "ry": 1, "rz": 1, "p": 1, "u": 3}
TWO_Q = ["cx", "cz", "swap"]
ARITY = {"cx": 2, "cz": 2, "swap": 2, "cp": 2, "ccx": 3}


def to_qiskit(text):
    """Build a Qiskit circuit from the shared text format (same parser rules as Julia)."""
    qc = None
    for raw in text.splitlines():
        line = raw.split("#")[0].strip()
        if not line:
            continue
        tok = line.split()
        if tok[0] == "n":
            qc = QuantumCircuit(int(tok[1]))
            continue
        name = tok[0]
        if name == "mcz":
            k = int(tok[1]); qs = [int(t) for t in tok[2:2 + k]]
            qc.append(ZGate() if k == 1 else ZGate().control(k - 1), qs)
            continue
        k = ARITY.get(name, 1)
        qs = [int(t) for t in tok[1:1 + k]]
        ps = [float(t) for t in tok[1 + k:]]
        if name == "id":
            qc.id(qs[0])
        elif name == "u":
            qc.u(*ps, qs[0])
        elif name in ("rx", "ry", "rz", "p"):
            getattr(qc, name)(ps[0], qs[0])
        elif name == "cp":
            qc.cp(ps[0], qs[0], qs[1])
        else:                                   # x y z h s sdg t tdg sx cx cz swap ccx
            getattr(qc, name)(*qs)
    return qc


def random_circuit_text(rng):
    n = int(rng.integers(1, 7))
    lines = [f"n {n}"]
    for _ in range(int(rng.integers(5, 60))):
        kinds = ["1q", "1qp"] + (["2q", "cp"] if n >= 2 else []) + (["ccx", "mcz"] if n >= 3 else [])
        kind = kinds[rng.integers(len(kinds))]
        if kind == "1q":
            lines.append(f"{rng.choice(ONE_Q)} {rng.integers(n)}")
        elif kind == "1qp":
            g = rng.choice(list(ONE_Q_PARAM))
            ps = " ".join(repr(float(x)) for x in rng.uniform(-2 * np.pi, 2 * np.pi, ONE_Q_PARAM[g]))
            lines.append(f"{g} {rng.integers(n)} {ps}")
        elif kind == "2q":
            a, b = rng.choice(n, 2, replace=False)
            lines.append(f"{rng.choice(TWO_Q)} {a} {b}")
        elif kind == "cp":
            a, b = rng.choice(n, 2, replace=False)
            lines.append(f"cp {a} {b} {repr(float(rng.uniform(-2*np.pi, 2*np.pi)))}")
        elif kind == "ccx":
            a, b, c = rng.choice(n, 3, replace=False)
            lines.append(f"ccx {a} {b} {c}")
        else:
            k = int(rng.integers(1, n + 1)); qs = rng.choice(n, k, replace=False)
            lines.append(f"mcz {k} " + " ".join(map(str, qs)))
    return "\n".join(lines) + "\n"


def read_state(path):
    a = np.loadtxt(path, ndmin=2)
    return a[:, 0] + 1j * a[:, 1]


def julia(script, *args):
    """Run a crosscheck script with the reference; True if it exited cleanly."""
    r = subprocess.run(JULIA + [f"--project={REFERENCE}", os.path.join(HERE, script), *args])
    return r.returncode == 0


failures = []
def report(label, ok, detail=""):
    print(f"  [{'PASS' if ok else 'FAIL'}] {label}" + (f"  ({detail})" if detail else ""))
    if not ok:
        failures.append(label)


def need(path):
    """A missing input is a failure, not a reason to skip the check."""
    ok = os.path.exists(path)
    if not ok:
        report(f"input present: {os.path.relpath(path)}", False)
    return ok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--n-random", type=int, default=500)
    ap.add_argument("--seed", type=int, default=1234)
    args = ap.parse_args()
    rng = np.random.default_rng(args.seed)
    print(f"qiskit {qiskit.__version__}, numpy {np.__version__}")

    print("-- A. random circuits ---------------------------------")
    with tempfile.TemporaryDirectory() as d:
        texts = []
        for i in range(args.n_random):
            t = random_circuit_text(rng); texts.append(t)
            with open(os.path.join(d, f"c{i:04d}.txt"), "w") as io:
                io.write(t)
        julia("run_circuits.jl", d)       # a circuit it throws on has no .state: a mismatch below
        worst, nbad, ngates, nerr = 0.0, 0, 0, 0
        for i, t in enumerate(texts):
            ref = Statevector.from_instruction(to_qiskit(t)).data
            path = os.path.join(d, f"c{i:04d}.state")
            if os.path.exists(path):
                got = read_state(path)
                err = np.max(np.abs(ref - got)) if got.shape == ref.shape else np.inf
            else:
                err = np.inf; nerr += 1
            worst = max(worst, err)
            ngates += len(t.splitlines()) - 1
            if err > ATOL:
                nbad += 1
                if nbad <= 3:
                    print("    first mismatch:\n" + t)
        report(f"{args.n_random} random circuits ({ngates} gates) match Qiskit amplitude-for-amplitude",
               nbad == 0, f"worst |d| = {worst:.1e}, mismatches = {nbad}, of which the simulator threw on {nerr}")

    with tempfile.TemporaryDirectory() as out:
        report("export.jl ran on the reference", julia("export.jl", out))

        print("-- B. lesson circuits ----------------------------------")
        files = sorted(glob.glob(os.path.join(out, "circuits", "*.txt")))
        report("9 lesson circuits exported", len(files) == 9, f"found {len(files)}")
        if need(os.path.join(out, "drift.txt")):
            drift = open(os.path.join(out, "drift.txt")).read().split()
            report("lesson circuits rebuilt from the reference equal lesson_circuits/", not drift,
                   "differ: " + ", ".join(drift) if drift else "")
        for f in files:
            if not need(f[:-4] + ".state"):
                continue
            ref = Statevector.from_instruction(to_qiskit(open(f).read())).data
            got = read_state(f[:-4] + ".state")
            err = np.max(np.abs(ref - got))
            report(os.path.basename(f)[:-4], err < ATOL, f"|d| = {err:.1e}")

        print("-- C. against Qiskit's own algorithm implementations ---")
        for n in range(1, 7):
            f = os.path.join(out, "qft", f"qft{n}.txt")
            if not need(f):
                continue
            ours = Operator(to_qiskit(open(f).read())).data
            lib = Operator(QFTGate(n)).data
            err = np.max(np.abs(ours - lib))
            report(f"QFT n={n}: our circuit's unitary == qiskit QFTGate", err < ATOL, f"|d| = {err:.1e}")
        t, phi = 5, 0.3
        f = os.path.join(out, "circuits", "lesson07_qpe_t5.state")
        if need(f):
            qpe = phase_estimation(t, PhaseGate(2 * np.pi * phi))
            qc = QuantumCircuit(t + 1); qc.x(t); qc.compose(qpe, range(t + 1), inplace=True)
            p_lib = Statevector.from_instruction(qc).probabilities(list(range(t)))
            p_ours = Statevector(read_state(f)).probabilities(list(range(t)))
            # FINDING (Qiskit 2.x, kept from the original): phase_estimation
            # appends a PermutationGate that bit-REVERSES the evaluation register
            # after the inverse QFT, so its readout index is bitreverse(y), not y.
            # It is undone explicitly instead of hiding the difference.
            bitrev = lambda y: int(format(y, f"0{t}b")[::-1], 2)
            p_lib_unrev = np.array([p_lib[bitrev(y)] for y in range(2 ** t)])
            err = np.max(np.abs(p_lib_unrev - p_ours))
            report("QPE t=5, phi=0.3: == qiskit phase_estimation (after undoing its bit-reversal)", err < ATOL,
                   f"|d| = {err:.1e}, argmax = {int(np.argmax(p_ours))} (phi*32 = 9.6)")
            report("...and WITHOUT undoing it they differ (the convention gap is real)",
                   np.max(np.abs(p_lib - p_ours)) > 0.1)
            tb = QuantumCircuit(t + 1); tb.x(t)
            for j in range(t):
                tb.h(j); tb.cp(2 * np.pi * phi * 2 ** j, j, t)
            tb.append(QFTGate(t).inverse(), range(t))
            p_tb = Statevector.from_instruction(tb).probabilities(list(range(t)))
            err = np.max(np.abs(p_tb - p_ours))
            report("QPE t=5, phi=0.3: == textbook QPE built in Qiskit with QFTGate^dagger", err < ATOL,
                   f"|d| = {err:.1e}")

        print("-- D. noise channels vs qiskit.quantum_info -----------")
        f = os.path.join(out, "noise_ghz3_rho.txt")
        if need(f):
            qc = QuantumCircuit(3); qc.h(0); qc.cx(0, 1); qc.cx(1, 2)
            g = 0.3
            amp = Kraus([np.array([[1, 0], [0, np.sqrt(1 - g)]]), np.array([[0, np.sqrt(g)], [0, 0]])])
            p = 0.2
            I = np.eye(2); X = np.array([[0, 1], [1, 0]]); Y = np.array([[0, -1j], [1j, 0]]); Z = np.diag([1, -1])
            dep = Kraus([np.sqrt(1 - 3 * p / 4) * I] + [np.sqrt(p / 4) * P for P in (X, Y, Z)])
            rho = DensityMatrix.from_instruction(qc).evolve(amp, qargs=[1]).evolve(dep, qargs=[2]).data
            a = np.loadtxt(f); ours = (a[:, 0] + 1j * a[:, 1]).reshape(8, 8)   # row-major i, j
            err = np.max(np.abs(rho - ours))
            report("GHZ3 + amplitude damping(q1) + depolarizing(q2): rho == Qiskit", err < ATOL,
                   f"|d| = {err:.1e}")

    print("\n" + ("ALL QISKIT CROSS-CHECKS PASSED" if not failures else f"{len(failures)} CROSS-CHECKS FAILED"))
    sys.exit(0 if not failures else 1)


if __name__ == "__main__":
    main()
