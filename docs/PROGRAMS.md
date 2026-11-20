# Programs

Status: format and the first program (`interval`, core course) built on
2026-11-18. The private-solutions mode was decided that day (Adam:
"encrypted bundle"). Section 6 lists what is not done.

A **program** is the last project of a course: the learner builds a package
alone, from a milestone spec, with as little help as the tutor can give and
still be useful. It uses the guided-project format (docs/GUIDED.md) with two
differences:

1. **The solution is sealed.** The reference, the hidden acceptance tests,
   the mutants and the fixtures live encrypted in
   `projects/programs/<p>/sealed.txt`, so reading the repository does not
   show them. `tutor program reveal` writes the reference into the learner's
   folder once every milestone has passed there.
2. **Hints are capped.** A check shows at most `[program] hint_cap` hint
   levels (1 for `interval`): a nudge toward the idea, never the answer. A
   guided project fades hints from 1 to 3 as failures repeat; a program
   stops at the cap.

A program follows the course's capstone and does not replace it
(COURSES_PLAN.md §6): the capstone teaches a method with a rubric, the
program tests whether the learner can work alone.

## 1. Commands

```bash
./tutor program list
./tutor program show interval [m]          # the spec of milestone m (plain; never sealed)
./tutor program start interval work/iv     # GUIDE.md with milestone 0
./tutor program check work/iv [m]          # as `guided check`, hints capped
./tutor program quiz interval 2
./tutor program reveal work/iv             # writes work/iv/solution/{src,test}, README.md
./tutor program seal interval [--check]    # author: encrypt private/ into sealed.txt
./tutor program verify [interval]          # author: seal current + the guided self-test
```

Checks are recorded in `.tutor/guided.toml` under the same
`<name>:<folder>` keys as guided projects, so progress and the course pages
count them. A program's name may not be a guided project's name
(`program verify` and `validate_courses` both check).

## 2. Files

```
projects/programs/
  self-study.key             64 hex digits: the self-study key (section 3)
  <p>/project.toml           plain: milestones, API, behaviours, hints, questions,
                             `course = "<id>"`, [program] follows, hint_cap
  <p>/sealed.txt             the encrypted bundle (committed)
  <p>/private/               the author's plain files (gitignored, never committed):
                             reference/{src,test}, acceptance/m<k>.jl, mutants.toml,
                             fixtures/, fixtures.toml
```

`project.toml` stays plain because the learner needs the spec; it holds no
code from the reference. The site data (`site/data/guided.json`) lists the
program with `"kind": "program"` and carries only what `project.toml` says.

Loading (src/programs.jl): `load_program` decrypts the bundle into a
temporary folder laid out like `projects/guided/<p>/`, once per process, and
loads it with `Guided.load_guided`. Everything after that, the sandboxed
driver, `assess`, the mutants, is the guided code unchanged.

## 3. Sealing and the two modes

The cipher uses the standard library only:

* keystream block i = SHA-256(key ‖ nonce ‖ i as UInt64), XORed with the
  plaintext (the packed TOML `{files = {path => text}}`);
* tag = HMAC-SHA-256(key, nonce ‖ ciphertext), checked before anything is
  decrypted, so a wrong key or an edited file is refused rather than
  decrypted to garbage;
* nonce = the first 16 bytes of SHA-256(plaintext). Sealing the same files
  twice gives the same bytes, so `seal --check` compares instead of trusting
  a timestamp. The cost: two bundles with equal plaintext under one key are
  equal, which reveals nothing here.

The key is `JULIA_TUTOR_PROGRAM_KEY` (64 lowercase hex digits) when set,
else `projects/programs/self-study.key`.

* **Self-study mode** (what the repository ships): the key is committed. The
  tutor on the learner's machine must decrypt the reference to run their
  tests against it, so anyone who wants the solution can decrypt it. **This
  is a speed bump against accidental spoilers, not security.** It keeps the
  solution out of search results, file browsing and a casual `grep`.
* **Cohort mode:** the instructor seals with another key, keeps it out of
  the learners' copy, and runs `program check` on a machine that has it (for
  example a CI job with the key as a secret). Not built yet: no CI job or
  submission flow exists (section 6).

## 4. Authoring a program

1. Write `project.toml` as for a guided project, plus `course`, `[program]`
   and `status`. Add the program to the course manifest
   (`course/courses/<id>.toml`: `programs = ["<p>"]`) and, where it assesses
   an outcome, `assessed_by = [..., "program:<p>"]`.
2. Write `private/` exactly as the guided files would be (docs/GUIDED.md §4:
   acceptance testsets per behaviour id, exemplar tests, one-place mutants,
   fixtures with expected verdicts).
3. `./tutor program seal <p>`, then `./tutor program verify <p>`: the seal is
   current, hint_cap is 1 to 3, `course` is set, the name is free, and the
   whole guided self-test passes (the reference passes; every mutant fails
   its own behaviour's acceptance set and is killed by the exemplar tests;
   fixtures get their verdicts; output-question keys are measured).
4. Commit `project.toml` and `sealed.txt`, never `private/`. A reviewer
   without `private/` can still run `program verify` (it verifies the bundle).

## 5. The interval program (core)

`TinyIntervals`: closed intervals `[lo, hi]` of floats that always enclose
the exact result. Five milestones:

| m | Topic | Behaviours |
|---|---|---|
| 0 | the package by hand | package-layout |
| 1 | the type: invariants, `in` exact across number types, `show`, `mid`/`diam` that are safe at the ends | 6 |
| 2 | arithmetic with outward rounding (one `prevfloat`/`nextfloat` step: valid because Float64 rounds to nearest) and division by an interval holding zero | 7 |
| 3 | Base integration: `convert` that encloses, `promote_rule`, `==`/`hash` with signed zero, `^` with the exact range (the dependency problem) | 5 |
| 4 | `roots(f, a)` by bisection with a proven discard rule, a tolerance and a box cap | 6 |

24 mutants, 6 fixtures. Every enclosure is tested against exact results in
512-bit BigFloat with directed rounding, not against a tolerance.

## 6. Known gaps

* The self-study key is in the repository (section 3). The lock stops
  accidents only.
* Cohort mode has no CI job, submission flow or key distribution yet.
* The site shows a program's spec and commands; it cannot run checks (no
  site page runs Julia).
* `reveal` trusts `.tutor/guided.toml`, which the learner can edit. That is
  acceptable for self-study (the key is public anyway) and not for cohorts.
* The choice-question keys are a reviewer's judgement, as in every unit.
* Only `interval` is built. The science, scicomp and sciml programs
  (COURSES_PLAN.md §6) need their envs in the sandbox, and the sciml one
  needs M4 and M7.
