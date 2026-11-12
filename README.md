# julia-tutor

A symbolic, deterministic tutor for scientific computing and scientific ML in
Julia, with no LLM in the feedback loop. Behavioural tests define correctness, a
static checker flags novice misconceptions, and an `explain` step joins test
failures, findings, measurements and a measured test-to-hole map to say where to
start.

Four courses (`./tutor courses`; `course/courses/*.toml`):

| Course | Role | Status |
|---|---|---|
| Core Julia | the way in | ready |
| Julia for science | the packages in between | ready |
| Scientific computing | destination | ready |
| Scientific ML | destination | **in progress** |

"Ready" means every unit is published with recorded outputs and graders that
pass their own tests; it says nothing yet about how well the courses teach. No
learner has taken one: time estimates on the site are computed from counts,
not measured, until a pilot runs.

Core Julia's project is **symdiff**, a from-scratch computer-algebra core (typed
term trees, canonical simplification, differentiation by multiple dispatch,
pattern matching, rewriting with a termination measure), with holes to fill. It
has no dependency on Symbolics.jl, SymbolicUtils.jl or Metatheory.jl.

```bash
juliaup add 1.10.13
source scripts/env.sh
JULIA_PKG_OFFLINE=false julia_pinned --project=. -e 'using Pkg; Pkg.instantiate()'
(cd projects/symdiff/reference && JULIA_PKG_OFFLINE=false julia_pinned --project=. -e 'using Pkg; Pkg.instantiate()')

./tutor start symdiff 1 work/s1
./tutor explain symdiff work/s1 --hints=1
./tutor lesson L01
```

* `CLAUDE.md`: roles, invariants, milestones, how to continue the work.
* `docs/DESIGN.md`: project choice, tool landscape, checker platform,
  sandboxing and latency, what is not stable.
* Website: lessons, explain gallery, hole map and rules, built from the same
  verified data (`site/`, `web/`; deployed to GitHub Pages by CI).

Status: M1 slice + M2 (explain fixtures, learner model) + course (C1) + website. `tutor serve`, which runs
code sent by the website, runs it in a Docker container with no network and no access to your files
(`./tutor sandbox pull <course>` once, or `build`; `--sandbox=none` opts out; [docs/START_CORE.md](docs/START_CORE.md)). The CLI test runner (`tutor test`) still runs plain
processes: only run your own code with it.
