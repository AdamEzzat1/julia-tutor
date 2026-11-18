"""
Which cross-check layer catches which seeded mutant? Re-measures the
original's per-layer table (projects/qsim/README.md) for the two external
layers, instead of quoting it.

For each [[mutant]] of projects/qsim/mutants.toml: copy the reference to a
temporary directory, apply the find/replace, and run the Qiskit diff and the
Yao diff against that copy (QSIM_REFERENCE). Each layer's verdict:
  FAIL   a comparison with the other simulator failed (caught numerically)
  drift  only the "rebuilt lesson circuits equal lesson_circuits/" guard failed
  crash  the run failed without reporting a comparison
  pass   the layer missed the mutant
The unit/lesson layer is `tutor holemap qsim` (holemap.toml [seeded]).

    python projects/qsim/crosscheck/mutant_layers.py [--only ID ...] [--n-random 100]

Slow (two Julia runs per mutant); author-side, not part of CI.
JULIA as for qiskit_diff.py.
"""
import argparse, os, shlex, shutil, subprocess, sys, tempfile, tomllib

HERE = os.path.dirname(os.path.abspath(__file__))
QSIM = os.path.dirname(HERE)
JULIA = shlex.split(os.environ.get("JULIA", "julia"))


DRIFT = "lesson circuits rebuilt from the reference equal lesson_circuits/"


def layer(cmd, ref):
    env = dict(os.environ, QSIM_REFERENCE=ref)
    r = subprocess.run(cmd, env=env, capture_output=True, text=True, encoding="utf-8", errors="replace")
    fails = [l for l in r.stdout.splitlines() if l.strip().startswith("[FAIL]")]
    if r.returncode == 0:
        return "pass"
    if any(DRIFT not in l for l in fails):
        return "FAIL"
    return "drift" if fails else "crash"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*")
    ap.add_argument("--n-random", type=int, default=100)
    args = ap.parse_args()
    with open(os.path.join(QSIM, "mutants.toml"), "rb") as io:
        mutants = tomllib.load(io)["mutant"]
    if args.only:
        mutants = [m for m in mutants if m["id"] in args.only]
    rows = []
    for m in mutants:
        with tempfile.TemporaryDirectory() as d:
            ref = os.path.join(d, "reference")
            shutil.copytree(os.path.join(QSIM, "reference"), ref)
            path = os.path.join(ref, "src", m["file"])
            src = open(path, encoding="utf-8").read()
            if src.count(m["find"]) != 1:
                sys.exit(f"{m['id']}: find must occur exactly once in {m['file']}")
            open(path, "w", encoding="utf-8").write(src.replace(m["find"], m["replace"]))
            q = layer([sys.executable, os.path.join(HERE, "qiskit_diff.py"), "--n-random", str(args.n_random)], ref)
            y = layer(JULIA + [f"--project={os.path.join(HERE, 'yao')}", os.path.join(HERE, "yao_diff.jl"),
                               str(args.n_random)], ref)
        rows.append((m["id"], q, y))
        print(f"{m['id']:16s} qiskit {q:5s}  yao {y:5s}", flush=True)
    print("\n| mutant | qiskit | yao |\n|---|---|---|")
    for r in rows:
        print(f"| {r[0]} | {r[1]} | {r[2]} |")


if __name__ == "__main__":
    main()
