# The course: units from absolute basics to advanced Julia and its ecosystem.
#
# A unit (course/units/<id>.toml) is prose sections with runnable examples, plus
# practice problems graded by actually running the learner's code.
#
# * Example outputs are never typed by hand. `tutor course record` runs every
#   example in a fresh process of the pinned Julia (the same path the sandbox
#   uses) and stores the output in course/outputs/<unit>.toml, keyed by a hash of
#   the code; `tutor course verify` re-runs them and fails on any difference.
# * Every problem has a hidden reference solution. Correctness compares the
#   learner's function with the reference on explicit and seeded random cases;
#   performance is measured relative to the reference in the same process, so
#   the verdict does not depend on how fast the learner's machine is.
# * Every problem lists variants: deliberately wrong, slow, allocating or
#   type-unstable solutions with the verdicts the grader must give them. They
#   are to the grader what mutation tests are to the hole map: proof that the
#   feedback says what it claims, checked by `tutor course verify`.

module Course

using TOML, SHA

export Unit, Section, Example, Question, Problem, Perf, Variant, load_course, validate_course,
       example_key, outputs_path, load_outputs, env_dir, TRACKS, TRACK_REQUIRES, find_problem,
       CourseInfo, Outcome, load_courses, validate_courses, course_of, prereq_unit, prereq_course

const COURSE_DIR = normpath(joinpath(@__DIR__, "..", "course"))
const TRACKS = ["foundations", "core", "advanced", "ecosystem", "scicomp", "sciml"]
# A track that assumes whole earlier tracks: every unit of those comes first in
# the syllabus, and each of its units names the earlier units it builds on.
const TRACK_REQUIRES = Dict("scicomp" => ["foundations", "core", "advanced", "ecosystem"],
                            "sciml" => ["foundations", "core", "advanced", "ecosystem", "scicomp"])
const DIFFICULTIES = ["warm-up", "core", "stretch"]
const VARIANT_EXPECT = ["correct", "incorrect", "load-error", "slow", "allocates", "unstable", "scaling", "fast"]

"""
Predict, then run (Phase 5): a prediction the learner commits before an
example's output is shown. The key is not typed: `measure` is a regex with one
capture group, read from the example's recorded output, and choice `i` holds
when the captured number lies in `ranges[i]` (half-open, `lo <= x < hi`) or the
captured word equals `values[i]` (case-insensitive). `tutor course verify`
fails unless exactly one choice holds and it is `answer`, so a re-recorded
output that changes the result also breaks the key.
"""
struct Prediction
    kc::String                               # the unit's knowledge component the hit rate counts for
    prompt::String
    measure::String
    choices::Vector{String}
    ranges::Vector{Tuple{Float64,Float64}}   # numeric predictions (empty for word predictions)
    values::Vector{String}                   # word predictions (empty for numeric ones)
    answer::Int                              # 1-based; must be the choice the measurement selects
    explain::String                          # shown with the output, whatever was picked
end

"""
Method-choice checkpoint (Phase 5): the learner picks a method (a solver, a
step size, a preconditioner) and writes a one-line reason before the
example's work-precision output is shown; then the choice is scored against
that output. Nothing is typed as a key: `rows[i]` is a regex matched in the
output, its numbered capture groups are numbers summed into choice `i`'s cost
(steps, calls, iterations: counts, never wall time), and an optional group
named `ok` must capture `true` for the choice to meet the accuracy the
example asks for. Among the choices that meet it, those within `band` times
the cheapest cost are *good*; the rest are *costly*, and a choice that misses
the accuracy *fails*. `tutor course verify` re-runs the example and fails
unless the measured good set equals `good`, and unless every cost ratio is at
least `CHOICE_MARGIN` away from the band's edge, so the verdict cannot be
flipped by a few percent of drift in the counts. That second rule is why a
checkpoint may sit on a `check = false` example (counts that move a little
between CPUs): its digits are not compared, its verdict is, on every verify.
The reason is never graded (there is no model of free text here); it is
stored in the browser and shown back next to the measurements.
"""
struct Checkpoint
    kc::String
    prompt::String
    choices::Vector{String}
    rows::Vector{String}            # one regex per choice: summed numeric captures, optional `ok` group
    cost::String                    # what the cost counts, shown in the table ("right-hand-side calls")
    band::Float64                   # good = within `band` times the cheapest choice that meets the accuracy
    good::Vector{Int}               # declared good choices (1-based); must equal the measured set
    explain::String                 # shown with the measurements, whatever was picked
    misconceptions::Vector{String}  # one per choice; required for every choice that is not good
end

# A cost ratio this close to the band's edge (within this factor either way)
# could change verdict with a small drift in the counts; verify refuses it.
const CHOICE_MARGIN = 1.5

"""
Break it (Phase 5): the learner looks for the value of a parameter (a step
size, a start point, a rate ratio) where a method stops working, and commits
that edge before the example's sweep is shown. Nothing is typed as a key: the
example's output is a sweep, one line per parameter value, and `row` is a
regex with named groups `p` (the value) and `m` (the measurement) matched on
every line. The method *fails* at a value when `m > limit` (`fails =
"above"`) or `m < limit` (`"below"`), or when `m` is NaN. Sorted by `p`, the
sweep must change from working to failing exactly once, and the two values
either side of that change are the measured edge, which must equal the
declared `edge`; `tutor course verify` re-checks both on the fresh run (the
example must have `check = true`). `probe` is the same computation at one
value, with `{{p}}` where the value goes: the site runs it at the learner's
value through `tutor serve`, and verify runs it at both ends of the edge and
requires the first to work and the second to fail, so the probe and the
sweep measure the same thing.
"""
struct BreakIt
    kc::String
    prompt::String
    param::String                  # the parameter's name as the learner sees it ("h", "x0")
    measure::String                # what `m` is, the table's column header ("|u| after 100 steps")
    row::String                    # regex with named groups `p` and `m`, matched on every output line
    fails::String                  # "above": failed when m > limit; "below": when m < limit
    limit::Float64
    edge::Tuple{Float64,Float64}   # declared: the swept values either side of the change, low then high
    close::Float64                 # a committed value within this factor of the edge is "close"
    probe::String                  # one run at one value: `{{p}}` is replaced by the value
    explain::String                # shown with the sweep, whatever was committed
    short::String                  # feedback for a value where the method still works
    past::String                   # feedback for a value well past the edge, where it already fails
end

# The sweep needs this many rows for an edge to mean something.
const BREAK_MIN_ROWS = 4

"""One axis of an explorer's grid: a named group of `row`, its label, and whether it is drawn on a log scale."""
struct ExploreAxis
    group::String
    label::String
    log::Bool
end

"""
Precomputed explorer (Phase 5): sliders over a grid of results that the
example's own output recorded (error against step size for three methods,
growth against a stability number). Nothing is typed as data: `row` is a
regex with one named group per axis and one for the `measure`, matched on
every output line, and the matched lines must form a full grid (every
combination of the axes' values exactly once). The site shows a slider (or,
for an axis whose values are words, buttons) per axis, the measure at the
chosen point as printed, and a plot of the measure against axis `x`, one
line per value of `series` if there is one. It is labelled as precomputed
by the reference; the example's code can be edited and run with `tutor
serve`. `tutor course verify` re-runs the example (it must have `check =
true`), so a changed grid is a changed output.
"""
struct Explorer
    kc::String
    prompt::String                 # what to try with the sliders
    row::String                    # regex: a named group per axis, and one named `measure`'s group
    axes::Vector{ExploreAxis}      # in the order the sliders are shown
    x::String                      # the axis on the plot's horizontal (numeric)
    series::String                 # the axis drawn as one line per value; "" = none
    measure::String                # the measured group
    label::String                  # what the measure is ("max error at t = 2")
    log::Bool                      # the measure on a log scale
    explain::String                # shown under the explorer
end

# Grids bigger than this make the site data heavy and the sliders coarse to use.
const EXPLORE_MAX_POINTS = 400
const EXPLORE_MAX_AXES = 3

struct Example
    code::String
    check::Bool          # false: output varies run to run (timings, threads); recorded, not compared
    caption::String      # introduces the example; shown above the code
    mode::String         # "repl" (default: REPL soft scope, like the sandbox) or "file" (include semantics)
    notice::String       # what to look at in the result; shown under the output (and figures)
    predict::Union{Nothing,Prediction}   # commit a prediction before the output is shown
    choose::Union{Nothing,Checkpoint}    # pick a method and give a reason before the output is shown
    breakit::Union{Nothing,BreakIt}      # find where the method fails before the sweep is shown
    explore::Union{Nothing,Explorer}     # sliders over the grid the output recorded
end
Example(code, check, caption, mode) = Example(code, check, caption, mode, "", nothing, nothing, nothing, nothing)
Example(code, check, caption, mode, notice) = Example(code, check, caption, mode, notice, nothing, nothing, nothing, nothing)
Example(code, check, caption, mode, notice, predict) =
    Example(code, check, caption, mode, notice, predict, nothing, nothing, nothing)
Example(code, check, caption, mode, notice, predict, choose) =
    Example(code, check, caption, mode, notice, predict, choose, nothing, nothing)
Example(code, check, caption, mode, notice, predict, choose, breakit) =
    Example(code, check, caption, mode, notice, predict, choose, breakit, nothing)

"""
A concept question shown after a section's examples. `choice`: pick the
right statement. `output`: `code` is run when the unit is recorded, and the
right choice must be exactly its output (so the key is measured, not typed).
Every wrong choice carries the misconception it stands for, shown when the
learner picks it.
"""
struct Question
    kind::String                  # "choice" or "output"
    prompt::String
    code::String                  # shown above the choices; required for "output"
    choices::Vector{String}
    answer::Int                   # 1-based index into `choices`
    explain::String               # why the right answer is right (shown after any answer)
    misconceptions::Vector{String}  # one per choice; "" for the right one
end

"""
An analogy shown beside a section's prose, for readers new to the field.
`breaks` is required: where the analogy stops matching the mathematics, so
the picture never replaces the definition it illustrates.
"""
struct Analogy
    title::String
    text::String
    breaks::String
end

"""
A hand-drawn SVG diagram, `course/diagrams/<unit>/<file>`. `alt` describes
what the diagram shows in words (for screen readers, and as a check that the
picture says something the prose can state).
"""
struct Diagram
    file::String
    alt::String
    caption::String
end

"""
A published source: a paper, book or official documentation page that a
unit cites. `url` must be public (https); `note` says what in the unit it
supports, in the unit's own words.
"""
struct Reference
    id::String
    authors::String
    title::String
    venue::String
    year::Int
    url::String
    note::String
end

struct Section
    title::String
    body::String
    examples::Vector{Example}
    questions::Vector{Question}
    analogies::Vector{Analogy}
    diagrams::Vector{Diagram}
    refs::Vector{String}          # ids of the unit's references this section rests on
end
Section(title, body, examples, questions) = Section(title, body, examples, questions, Analogy[], Diagram[], String[])

struct Perf
    args::String         # Julia expression(s) for the arguments, with `rng` and `n` in scope
    sizes::Vector{Int}   # two sizes: the ratio of times estimates the growth exponent
    mutates::Bool        # the function changes its arguments: fresh copy per call
end

struct Variant
    label::String
    code::String
    expect::Vector{String}   # verdicts the grader must give (see VARIANT_EXPECT)
end

"""
A convergence test of a find-the-bug problem: Julia source appended to the
learner's code (it calls the entry function), run in a fresh process, that
prints one line matched by `row` (a regex with a named group `m`, the measured
number). The test passes when `expect[1] <= m <= expect[2]`. `explain` is the
measured feedback shown when it fails: what the measurement means, never
where the error is.
"""
struct BugTest
    name::String                     # shown in the table ("observed order on y' = -y + cos t")
    code::String
    row::String
    expect::Tuple{Float64,Float64}   # inclusive; derived in a comment next to it in the unit
    explain::String
end

"""
Find the bug (Phase 5): a plausible solver with one planted error. The
starter is not written by hand: it is the reference with `find` replaced by
`replace`, which must occur exactly once and change exactly one line, so the
learner fixes one line of otherwise correct code. The convergence tests are
measured: `tutor course verify` requires every test to pass on the reference
and at least one to fail on the planted starter. Hints fade: first the
failing tests and what each measures, then the problem's `hints` one at a
time; `answer_tokens` (pieces of the fix) may not appear in a test's text or
the first hint. Once the learner's code passes the grader, `misconception`
says what belief the planted line models.
"""
struct Bug
    kc::String
    find::String
    replace::String
    tests::Vector{BugTest}
    misconception::String
    answer_tokens::Vector{String}
end

"""
A distractor line of a Parsons problem: it can take the place of the movable
line `replaces` (1-based), and stands for `misconception`.
"""
struct Distractor
    line::String
    replaces::Int
    misconception::String
end

"""
Parsons problem (Phase 5): the learner puts the reference's lines in order.
The first `head` and last `tail` lines of the reference stay fixed; the lines
between them are shuffled, together with the distractors. Lines keep their
indentation, which must match the block structure (4 spaces per level), so an
ordering whose indentation contradicts its `for`/`end` nesting is rejected
before it is run. Which orderings work is measured: `tutor course record`
runs every arrangement (one of each line/distractor pair, every order) that
parses and is indented consistently on the problem's cases and stores those
that match the reference; `verify` re-runs it and requires the reference's own
order to be accepted and no ordering with a distractor to be.
"""
struct Parsons
    kc::String
    head::Int
    tail::Int
    distractors::Vector{Distractor}
end

struct Problem
    id::String
    title::String
    difficulty::String
    kcs::Vector{String}
    prompt::String
    entry::String            # the function the learner must define
    starter::String
    reference::String        # hidden from the website; the repo is public, so it is not a secret
    cases::Vector{String}    # argument lists as source, e.g. "[3, 1, 2], 2"
    gen::String              # `rng -> [argument tuples...]`, seeded; "" for none
    compare::String          # "isequal", "isapprox" or "custom" (then `checker`)
    checker::String          # custom: `(got, expected) -> Bool`, evaluated with the env's packages
    rtol::Float64
    check_type::Bool         # result type must equal the reference's (3 vs 3.0 matters in Julia)
    compare_args::Bool       # in-place functions: compare the mutated arguments too
    hints::Vector{String}
    perf::Union{Nothing,Perf}
    variants::Vector{Variant}
    threads::Int             # Julia threads for grading (1; more for problems about threads)
    repeats::Int             # times each case runs: >1 catches data races
    packages::Vector{String} # packages loaded for cases/gen/checker; empty = every package of the env
    bug::Union{Nothing,Bug}  # find the bug: the starter is the reference with one planted error
    parsons::Union{Nothing,Parsons}  # put the reference's lines in order
end
Problem(id, title, difficulty, kcs, prompt, entry, starter, reference, cases, gen, compare, checker, rtol,
        check_type, compare_args, hints, perf, variants, threads, repeats, packages) =
    Problem(id, title, difficulty, kcs, prompt, entry, starter, reference, cases, gen, compare, checker, rtol,
            check_type, compare_args, hints, perf, variants, threads, repeats, packages, nothing, nothing)
Problem(id, title, difficulty, kcs, prompt, entry, starter, reference, cases, gen, compare, checker, rtol,
        check_type, compare_args, hints, perf, variants, threads, repeats, packages, bug) =
    Problem(id, title, difficulty, kcs, prompt, entry, starter, reference, cases, gen, compare, checker, rtol,
            check_type, compare_args, hints, perf, variants, threads, repeats, packages, bug, nothing)

"""The reference with the planted error (the starter of a find-the-bug problem); `nothing` unless `find` occurs once."""
plant(reference::AbstractString, b::Bug) =
    isempty(b.find) || count(b.find, reference; overlap = true) != 1 ? nothing : replace(reference, b.find => b.replace)

struct Unit
    id::String
    title::String
    track::String
    env::String              # "base" (stdlib only) or a pinned environment under course/envs/
    status::String           # "ready" or "planned" (planned units have an outline only)
    summary::String
    kcs::Vector{String}
    prerequisites::Vector{String}
    outline::Vector{String}  # for planned units: what the unit will cover
    lessons::Vector{String}  # predict-the-output lessons (lessons/*.toml) that go with this unit
    sections::Vector{Section}
    problems::Vector{Problem}
    references::Vector{Reference}
end
Unit(id, title, track, env, status, summary, kcs, prerequisites, outline, lessons, sections, problems) =
    Unit(id, title, track, env, status, summary, kcs, prerequisites, outline, lessons, sections, problems, Reference[])

getstr(d, k, default = "") = String(get(d, k, default))

function load_question(q)
    choices = String.(get(q, "choices", String[]))
    mis = String.(get(q, "misconceptions", fill("", length(choices))))
    return Question(getstr(q, "kind", "choice"), getstr(q, "prompt"), getstr(q, "code"), choices,
                    Int(get(q, "answer", 0)), getstr(q, "explain"), mis)
end

"""Every concept question of a unit, in order."""
questions(u) = [q for s in u.sections for q in s.questions]

"""Code a unit records: its examples, then the code of its `output` questions (REPL mode)."""
recorded_code(u) = vcat([(e.code, e.mode) for s in u.sections for e in s.examples],
                        [(q.code, "repl") for q in questions(u) if q.kind == "output"])

function load_problem(d)
    perf = haskey(d, "perf") ?
        Perf(d["perf"]["args"], Int.(d["perf"]["sizes"]), get(d["perf"], "mutates", false)) : nothing
    variants = [Variant(v["label"], v["code"], String.(v["expect"])) for v in get(d, "variant", Any[])]
    bug = load_bug(get(d, "bug", nothing))
    parsons = load_parsons(get(d, "parsons", nothing))
    reference = d["reference"]
    # A find-the-bug starter is generated from the reference; a hand-written one
    # (or a `find` that does not occur once) leaves a starter that validation rejects.
    # A Parsons starter is generated too: the fixed lines, with a gap between them.
    starter = bug !== nothing ? (haskey(d, "starter") ? BUG_STARTER_GIVEN : something(plant(reference, bug), "")) :
              parsons !== nothing ? (haskey(d, "starter") ? PARSONS_STARTER_GIVEN : parsons_starter(reference, parsons)) :
              d["starter"]
    return Problem(d["id"], d["title"], d["difficulty"], String.(get(d, "kcs", String[])), d["prompt"],
                   d["entry"], starter, reference, String.(get(d, "cases", String[])),
                   getstr(d, "gen"), getstr(d, "compare", "isequal"), getstr(d, "checker"), Float64(get(d, "rtol", 1e-8)),
                   get(d, "check_type", true), get(d, "compare_args", false),
                   String.(get(d, "hints", String[])), perf, variants,
                   Int(get(d, "threads", 1)), Int(get(d, "repeats", 1)), String.(get(d, "packages", String[])), bug, parsons)
end

const BUG_STARTER_GIVEN = "# a find-the-bug problem's starter is generated from the reference: remove `starter`\n"

function load_bug(b)
    b === nothing && return nothing
    tests = BugTest[]
    for t in get(b, "test", Any[])
        e = get(t, "expect", Any[])
        expect = length(e) == 2 && all(x -> x isa Real, e) ? (Float64(e[1]), Float64(e[2])) : (NaN, NaN)
        push!(tests, BugTest(getstr(t, "name"), getstr(t, "code"), getstr(t, "row"), expect, getstr(t, "explain")))
    end
    return Bug(getstr(b, "kc"), getstr(b, "find"), getstr(b, "replace"), tests, getstr(b, "misconception"),
               String.(get(b, "answer_tokens", String[])))
end

"""The line numbers (1-based) where two texts differ, or `nothing` when their line counts differ."""
function changed_lines(a::AbstractString, b::AbstractString)
    la, lb = split(a, '\n'), split(b, '\n')
    length(la) == length(lb) || return nothing
    return [i for i in eachindex(la) if la[i] != lb[i]]
end

"""Structural problems of a find-the-bug problem (no Julia run needed)."""
function bug_problems(p::Problem, kcs)
    b = p.bug
    out = String[]
    b.kc in kcs || push!(out, "kc '$(b.kc)' is not one of the unit's KCs")
    p.starter == BUG_STARTER_GIVEN && push!(out, "the starter is generated from the reference: remove `starter`")
    n = isempty(b.find) ? 0 : count(b.find, p.reference; overlap = true)
    n == 1 || push!(out, "`find` must occur exactly once in the reference (found $n times)")
    b.find == b.replace && push!(out, "`replace` equals `find`: nothing is planted")
    if n == 1 && b.find != b.replace
        ch = changed_lines(p.reference, plant(p.reference, b))
        ch !== nothing && length(ch) == 1 ||
            push!(out, "the planted error must change exactly one line of the reference (one error, one line to fix)")
    end
    isempty(strip(b.misconception)) && push!(out, "no misconception (what belief the planted line models)")
    isempty(b.answer_tokens) && push!(out, "no answer_tokens (pieces of the fix that the first hint and the tests may not show)")
    for tok in b.answer_tokens
        occursin(tok, b.find) || push!(out, "answer token \"$tok\" is not part of the fix (`find`)")
        occursin(tok, b.replace) && push!(out, "answer token \"$tok\" also appears in the planted line, so it cannot give the fix away")
    end
    isempty(p.hints) && push!(out, "no hints (they fade in after the measured tests)")
    length(b.tests) >= 1 || push!(out, "no convergence tests")
    names = Set{String}()
    for (i, t) in enumerate(b.tests)
        w = "test $i"
        isempty(t.name) && push!(out, "$w: no name")
        t.name in names && push!(out, "$w: duplicate name '$(t.name)'")
        push!(names, t.name)
        isempty(strip(t.code)) && push!(out, "$w: no code")
        isempty(strip(t.explain)) && push!(out, "$w: no explain (shown when it fails)")
        lo, hi = t.expect
        isfinite(lo) && isfinite(hi) && lo < hi || push!(out, "$w: expect must be two finite numbers, low then high")
        re = try
            Regex(t.row)
        catch err
            push!(out, "$w: row is not a valid regex ($(sprint(showerror, err)))"); nothing
        end
        re !== nothing && !has_group(re, "m") && push!(out, "$w: row needs a named group `m` (the measured number)")
        # Level-1 feedback is the tests' text: it may say what is measured, never the fix.
        for tok in b.answer_tokens
            for (what, txt) in (("name", t.name), ("explain", t.explain))
                occursin(tok, txt) && push!(out, "$w: the $what contains the answer token \"$tok\"")
            end
        end
    end
    for tok in b.answer_tokens
        !isempty(p.hints) && occursin(tok, p.hints[1]) && push!(out, "the first hint contains the answer token \"$tok\"")
    end
    return out
end

"""The measured value of a test from its output: `nothing` unless exactly one line matches `row`."""
function bug_test_value(t::BugTest, output::AbstractString)
    re = try Regex(t.row) catch; return nothing end
    ms = [m for m in (match(re, l) for l in split(output, '\n')) if m !== nothing]
    length(ms) == 1 || return nothing
    v = tryparse(Float64, something(ms[1]["m"], ""))
    return v
end

"""Whether a test's measured value passes (`nothing`: the run gave no reading, a fail)."""
bug_test_passes(t::BugTest, v) = v !== nothing && !isnan(v) && t.expect[1] <= v <= t.expect[2]

"""The code a convergence test runs: the learner's code, then the test."""
bug_test_code(code::AbstractString, t::BugTest) = rstrip(code) * "\n\n" * t.code

# ---- Parsons problems ----------------------------------------------------------

const PARSONS_STARTER_GIVEN = "# a Parsons problem's starter is generated from the reference: remove `starter`\n"
const PARSONS_MAX_ITEMS = 8         # movable lines; every arrangement is enumerated, so keep it small
const PARSONS_MAX_DISTRACTORS = 3

function load_parsons(d)
    d === nothing && return nothing
    ds = [Distractor(getstr(x, "line"), Int(get(x, "replaces", 0)), getstr(x, "misconception"))
          for x in get(d, "distractor", Any[])]
    return Parsons(getstr(d, "kc"), Int(get(d, "head", 0)), Int(get(d, "tail", 0)), ds)
end

"""The reference's lines: the fixed head, the movable lines in their working order, the fixed tail."""
function parsons_lines(reference::AbstractString, z::Parsons)
    ls = String.(split(rstrip(reference, '\n'), '\n'))
    n = length(ls) - z.head - z.tail
    n < 0 && return (head = ls, items = String[], tail = String[])
    return (head = ls[1:z.head], items = ls[z.head+1:z.head+n], tail = ls[z.head+n+1:end])
end
parsons_lines(p::Problem) = parsons_lines(p.reference, p.parsons)

"""Every line a learner can place: the movable lines, then the distractors (indices follow this order)."""
parsons_pool(p::Problem) = [parsons_lines(p).items; [d.line for d in p.parsons.distractors]]

"""
The pool index a line stands for when it is compared: the first index with the
same text (two `end` lines are interchangeable).
"""
parsons_canonical(pool, i) = findfirst(==(pool[i]), pool)

function parsons_starter(reference::AbstractString, z::Parsons)
    l = parsons_lines(reference, z)
    gap = isempty(l.items) ? "" : " "^parsons_indent(l.items[1]) * "# put the lines here, in order"
    return join([l.head; gap; l.tail], "\n") * "\n"
end

# How a Parsons ordering is read: indentation (4 spaces per level) is part of
# each line, so it must agree with the nesting the order creates.
# `parsons_depth(d, line)` is the block depth after `line` given the depth `d`
# before it, or -1 when the line's indentation is wrong for where it sits.
# One source, evaluated here and spliced into the enumeration script, so the
# validator and the recorder read indentation the same way.
const PARSONS_DEPTH_SRC = raw"""
parsons_indent(l) = length(l) - length(lstrip(l, ' '))
const PARSONS_OPENER = r"^(function|for|while|if|let|begin|try|struct|mutable struct|module|quote|macro)\b|\bdo(\s+[^#]*)?$"
const PARSONS_MIDDLE = r"^(else|elseif|catch|finally)\b"
function parsons_depth(depth::Int, line::AbstractString)
    depth < 0 && return -1
    s = lstrip(line)
    ind = parsons_indent(line)
    if s == "end" || startswith(s, "end ") || startswith(s, "end#")
        return ind == 4 * (depth - 1) ? depth - 1 : -1
    elseif occursin(PARSONS_MIDDLE, s)
        return ind == 4 * (depth - 1) ? depth : -1
    else
        ind == 4 * depth || return -1
        return occursin(PARSONS_OPENER, s) ? depth + 1 : depth
    end
end
parsons_depth(depth::Int, lines::AbstractVector) = foldl(parsons_depth, lines; init = depth)
"""
include_string(@__MODULE__, PARSONS_DEPTH_SRC, "PARSONS_DEPTH_SRC")

"""Structural problems of a Parsons problem (no Julia run needed)."""
function parsons_problems(p::Problem, kcs)
    z = p.parsons
    out = String[]
    z.kc in kcs || push!(out, "kc '$(z.kc)' is not one of the unit's KCs")
    p.starter == PARSONS_STARTER_GIVEN && push!(out, "the starter is generated from the reference: remove `starter`")
    p.compare in ("isequal", "isapprox") || push!(out, "compare must be isequal or isapprox (orderings are compared in one process)")
    p.compare_args && push!(out, "compare_args is not supported")
    p.threads == 1 && p.repeats == 1 || push!(out, "threads and repeats must be 1")
    isempty(p.gen) || push!(out, "gen is not used: orderings are checked on the explicit cases only")
    length(p.cases) >= 2 || push!(out, "needs at least two explicit cases (every ordering runs on them)")
    l = parsons_lines(p)
    z.head >= 1 && z.tail >= 1 || push!(out, "head and tail must each fix at least one line (the signature and the final `end`)")
    3 <= length(l.items) <= PARSONS_MAX_ITEMS || push!(out, "needs 3 to $PARSONS_MAX_ITEMS movable lines (found $(length(l.items)))")
    for (i, x) in enumerate([l.head; l.items; l.tail])
        isempty(strip(x)) && push!(out, "line $i of the reference is blank (every line is a card)")
        occursin('\t', x) && push!(out, "line $i of the reference has a tab (indent with spaces)")
    end
    any(x -> occursin(r"^\s*while\b", x), l.items) && push!(out, "a movable `while` could make an ordering loop forever")
    d0 = parsons_depth(0, l.head)
    d0 >= 1 || push!(out, "the head must open the function (the movable lines go inside it)")
    d0 >= 1 && parsons_depth(parsons_depth(d0, l.items), l.tail) != 0 &&
        push!(out, "the reference's own lines are not indented 4 spaces per block level")
    length(z.distractors) <= PARSONS_MAX_DISTRACTORS || push!(out, "at most $PARSONS_MAX_DISTRACTORS distractors")
    seen = Set{String}()
    for (k, d) in enumerate(z.distractors)
        w = "distractor $k"
        1 <= d.replaces <= length(l.items) || (push!(out, "$w: replaces must be 1 to $(length(l.items))"); continue)
        d.line in l.items && push!(out, "$w: the same text as a movable line")
        d.line in seen && push!(out, "$w: duplicate line")
        push!(seen, d.line)
        # Same indentation as the line it replaces, so indentation alone cannot give it away.
        parsons_indent(d.line) == parsons_indent(l.items[d.replaces]) ||
            push!(out, "$w: indent it like the line it replaces ($(parsons_indent(l.items[d.replaces])) spaces)")
        isempty(strip(d.misconception)) && push!(out, "$w: no misconception")
    end
    allunique(d.replaces for d in z.distractors) ||
        push!(out, "two distractors replace the same line")
    return out
end

"""
A Julia program that enumerates and runs every arrangement of a Parsons
problem's lines, as `tutor course record` runs it (in the unit's env). It
prints `accepted: i j k ...` (pool indices, canonical for repeated texts) for
each arrangement whose results equal the reference's on every case, and then
`parsons: <n> run`. Candidates are interpreted (`compile=min`), each in a new
module: thousands of them, each called a few times, so compiling would cost
far more than running.
"""
function parsons_script(p::Problem, usings::AbstractVector{<:AbstractString})
    l = parsons_lines(p)
    pool = parsons_pool(p)
    n = length(l.items)
    pairs = [(d.replaces, n + k) for (k, d) in enumerate(p.parsons.distractors)]
    cmp = p.compare == "isapprox" ?
        "(a, b) -> (try isapprox(a, b; rtol = $(p.rtol)) catch; isequal(a, b) end)" : "isequal"
    return """
    $(join(["using " * x for x in usings], "\n"))
    const HEAD = $(repr(l.head))
    const TAIL = $(repr(l.tail))
    const POOL = $(repr(pool))
    const N = $n
    const PAIRS = $(repr(pairs))
    const ENTRY = $(repr(Symbol(p.entry)))
    const CASES = Any[$(join(["($a,)" for a in p.cases], ", "))]
    const USINGS = $(repr(collect(String, usings)))
    const SAME = $cmp
    const CHECK_TYPE = $(p.check_type)
    $PARSONS_DEPTH_SRC
    $PARSONS_DRIVER
    """
end

# The enumeration itself, spliced into `parsons_script` after the constants
# and `parsons_depth`; it uses only Base. A prefix is extended only while its
# indentation is consistent, and a full arrangement runs only if it parses.
const PARSONS_DRIVER = raw"""
hashead(ex, hs) = ex isa Expr && (ex.head in hs || any(a -> hashead(a, hs), ex.args))
canon(i) = findfirst(==(POOL[i]), POOL)
const RUNS = Ref(0)
function results(order)
    ex = Meta.parseall(join([HEAD; POOL[order]; TAIL], "\n"))
    hashead(ex, (:error, :incomplete)) && return nothing
    RUNS[] += 1
    m = Module(:Candidate)
    Core.eval(m, :(Base.Experimental.@compiler_options compile=min infer=false optimize=0))
    f = try
        foreach(u -> Core.eval(m, Meta.parse("using " * u)), USINGS)
        Core.eval(m, ex)
        Core.eval(m, ENTRY)
    catch
        return nothing
    end
    return Any[try (:ok, Base.invokelatest(f, deepcopy(c)...)) catch e; (:throws, typeof(e)) end for c in CASES]
end
same(a, b) = a[1] == b[1] &&
    (a[1] === :throws ? a[2] == b[2] : SAME(a[2], b[2]) && (!CHECK_TYPE || typeof(a[2]) == typeof(b[2])))
function walk!(accepted, prefix, d, rest, d0, ref)
    if isempty(rest)
        parsons_depth(d, TAIL) == 0 || return
        r = results(prefix)
        r !== nothing && all(same(a, b) for (a, b) in zip(r, ref)) && push!(accepted, canon.(prefix))
        return
    end
    tried = Set{String}()
    for (i, j) in enumerate(rest)
        POOL[j] in tried && continue      # equal texts give equal programs
        push!(tried, POOL[j])
        d2 = parsons_depth(d, POOL[j])
        d2 < d0 && continue               # mis-indented (-1), or closes the function early
        walk!(accepted, [prefix; j], d2, deleteat!(copy(rest), i), d0, ref)
    end
end
function parsons_main()
    ref = results(collect(1:N))
    ref === nothing && (println("parsons: the reference's own order does not run"); return)
    d0 = parsons_depth(0, HEAD)
    accepted = Set{Vector{Int}}()
    for mask in 0:(2^length(PAIRS) - 1)
        pool = collect(1:N)
        for (k, (l, j)) in enumerate(PAIRS)
            (mask >> (k - 1)) & 1 == 1 && (pool[l] = j)
        end
        walk!(accepted, Int[], d0, pool, d0, ref)
    end
    foreach(a -> println("accepted: ", join(a, " ")), sort!(collect(accepted)))
    println("parsons: ", RUNS[], " run")
end
parsons_main()
"""

"""
The accepted orderings printed by `parsons_script`, as strings of pool indices
("1 2 3"), sorted; `nothing` when the run did not finish (no `parsons:` line).
"""
function parse_parsons_output(out::AbstractString)
    occursin(r"(?m)^parsons: \d+ run$", out) || return nothing
    return sort!([String(m[1]) for m in eachmatch(r"(?m)^accepted: ([\d ]+)$", out)])
end

"""A learner's arrangement (pool indices) in the form the accepted set is stored in."""
parsons_key(pool, order) = join([parsons_canonical(pool, i) for i in order], " ")

"""
Feedback on an arrangement (pool indices, 1-based) against the measured
accepted set, in this order: a line used twice or out of range (`:invalid`);
a distractor (`:distractor`, with its number); the wrong number of lines
(`:count`, with the number needed); a working order (`:solved`); otherwise the
longest prefix that starts some working order (`:prefix`, with its length).
`web/src/parsons.ts` gives the same answers (tested on the same vectors).
"""
function parsons_feedback(pool::AbstractVector, n::Int, accepted::AbstractVector{<:AbstractString}, order::AbstractVector{Int})
    all(i -> 1 <= i <= length(pool), order) && allunique(order) || return (kind = :invalid, value = 0)
    for i in order
        i > n && return (kind = :distractor, value = i - n)
    end
    length(order) == n || return (kind = :count, value = n)
    acc = [parse.(Int, split(a)) for a in accepted]
    key = [parsons_canonical(pool, i) for i in order]
    key in acc && return (kind = :solved, value = n)
    best = maximum(a -> something(findfirst(k -> a[k] != key[k], 1:n), n + 1) - 1, acc; init = 0)
    return (kind = :prefix, value = best)
end

"""
A fixed display order for the pool (so the CLI's letters do not change between
runs): sorted by an FNV-1a hash of the problem id and the line, which does not
depend on Julia's `hash` (that can change between releases).
"""
function parsons_display_order(id::AbstractString, pool::AbstractVector)
    fnv(s) = foldl((h, b) -> (h ⊻ UInt32(b)) * 0x01000193, codeunits(s); init = 0x811c9dc5)
    return sortperm([(fnv(id * "\n" * x), i) for (i, x) in enumerate(pool)])
end

# Git on Windows may check files out with CRLF; example keys hash the code, so
# normalise line endings or Windows and Linux would disagree.
normalize_nl(x::AbstractString) = replace(x, "\r\n" => "\n")
normalize_nl(x::AbstractDict) = Dict{String,Any}(k => normalize_nl(v) for (k, v) in x)
normalize_nl(x::AbstractVector) = Any[normalize_nl(v) for v in x]
normalize_nl(x) = x

function load_prediction(p)
    p === nothing && return nothing
    ranges = Tuple{Float64,Float64}[(Float64(r[1]), Float64(r[2])) for r in get(p, "ranges", Any[]) if length(r) == 2]
    length(ranges) == length(get(p, "ranges", Any[])) || (ranges = [(NaN, NaN)])   # malformed: validation says so
    return Prediction(getstr(p, "kc"), getstr(p, "prompt"), getstr(p, "measure"), String.(get(p, "choices", String[])),
                      ranges, String.(get(p, "values", String[])), Int(get(p, "answer", 0)), getstr(p, "explain"))
end

function load_checkpoint(c)
    c === nothing && return nothing
    choices = String.(get(c, "choices", String[]))
    return Checkpoint(getstr(c, "kc"), getstr(c, "prompt"), choices, String.(get(c, "rows", String[])),
                      getstr(c, "cost"), Float64(get(c, "band", 2.0)), Int.(get(c, "good", Int[])),
                      getstr(c, "explain"), String.(get(c, "misconceptions", fill("", length(choices)))))
end

function load_breakit(b)
    b === nothing && return nothing
    e = get(b, "edge", Any[])
    edge = length(e) == 2 && all(x -> x isa Real, e) ? (Float64(e[1]), Float64(e[2])) : (NaN, NaN)  # malformed: validation says so
    return BreakIt(getstr(b, "kc"), getstr(b, "prompt"), getstr(b, "param"), getstr(b, "measure"), getstr(b, "row"),
                   getstr(b, "fails"), Float64(get(b, "limit", NaN)), edge, Float64(get(b, "close", 1.25)),
                   getstr(b, "probe"), getstr(b, "explain"), getstr(b, "short"), getstr(b, "past"))
end

function load_explorer(x)
    x === nothing && return nothing
    axes = [ExploreAxis(getstr(a, "group"), getstr(a, "label"), get(a, "log", false) === true) for a in get(x, "axis", Any[])]
    return Explorer(getstr(x, "kc"), getstr(x, "prompt"), getstr(x, "row"), axes, getstr(x, "x"), getstr(x, "series"),
                    getstr(x, "measure"), getstr(x, "label"), get(x, "log", false) === true, getstr(x, "explain"))
end

function load_unit(path::String)
    d = normalize_nl(TOML.parsefile(path))
    sections = [Section(s["title"], s["body"],
                        [Example(e["code"], get(e, "check", true), getstr(e, "caption"), getstr(e, "mode", "repl"),
                                 getstr(e, "notice"), load_prediction(get(e, "predict", nothing)),
                                 load_checkpoint(get(e, "choose", nothing)), load_breakit(get(e, "breakit", nothing)),
                                 load_explorer(get(e, "explore", nothing)))
                         for e in get(s, "example", Any[])],
                        [load_question(q) for q in get(s, "question", Any[])],
                        [Analogy(getstr(a, "title"), getstr(a, "text"), getstr(a, "breaks")) for a in get(s, "analogy", Any[])],
                        [Diagram(getstr(g, "file"), getstr(g, "alt"), getstr(g, "caption")) for g in get(s, "diagram", Any[])],
                        String.(get(s, "refs", String[]))) for s in get(d, "section", Any[])]
    refs = [Reference(getstr(r, "id"), getstr(r, "authors"), getstr(r, "title"), getstr(r, "venue"),
                      Int(get(r, "year", 0)), getstr(r, "url"), getstr(r, "note")) for r in get(d, "reference", Any[])]
    return Unit(d["id"], d["title"], d["track"], getstr(d, "env", "base"), getstr(d, "status", "ready"),
                d["summary"], String.(get(d, "kcs", String[])), String.(get(d, "prerequisites", String[])),
                String.(get(d, "outline", String[])), String.(get(d, "lessons", String[])), sections,
                [load_problem(p) for p in get(d, "problem", Any[])], refs)
end

"""All units in syllabus order (file names start with a sortable number)."""
load_course(dir::String = COURSE_DIR) =
    [load_unit(joinpath(dir, "units", f)) for f in sort!(readdir(joinpath(dir, "units"))) if endswith(f, ".toml")]

find_problem(units, id) = (for u in units, p in u.problems; p.id == id && return (u, p); end; nothing)

# ---- courses (course/courses/<id>.toml) ---------------------------------------
#
# A course is an ordered list of existing unit ids: unit ids are global and
# never change, so recorded outputs (keyed by code), learner state (keyed by
# unit, problem and KC ids) and links stay valid when units are regrouped.
# A prerequisite in another course is written "<course>/<unit>"; one in the
# same course is the bare unit id.

const COURSE_STATUS = ["ready", "in-progress", "planned"]

struct Outcome
    text::String
    assessed_by::Vector{String}   # units of the course, "project:<p>", "guided:<p>"
    planned::Vector{String}       # cases and programs that will assess it (not built yet)
end

struct CourseInfo
    id::String
    title::String
    order::Int
    status::String
    summary::String
    requires::Vector{String}      # course ids this course assumes
    envs::Vector{String}          # exactly the envs its units and guided projects run in
    units::Vector{String}
    projects::Vector{String}      # hole projects (projects/<p>/holes.toml)
    guided::Vector{String}        # guided projects (projects/guided/<p>)
    outcomes::Vector{Outcome}
    download::String              # [setup] download: what `tutor sandbox pull <id>` fetches, e.g. "up to 0.62 GiB"
    download_measured::String     # [setup] measured: where that number was measured (a CI run, a date)
    status_note::String           # why a course is not ready; shown wherever its status is ("" when ready)
end
CourseInfo(id, title, order, status, summary, requires, envs, units, projects, guided, outcomes) =
    CourseInfo(id, title, order, status, summary, requires, envs, units, projects, guided, outcomes, "", "", "")

function load_course_info(path::String)
    d = normalize_nl(TOML.parsefile(path))
    strs(k) = String.(get(d, k, String[]))
    outs = [Outcome(o["text"], String.(get(o, "assessed_by", String[])), String.(get(o, "planned", String[])))
            for o in get(d, "outcome", Any[])]
    setup = get(d, "setup", Dict{String,Any}())
    return CourseInfo(d["id"], d["title"], Int(d["order"]), getstr(d, "status", "ready"), d["summary"],
                      strs("requires"), strs("envs"), strs("units"), strs("projects"), strs("guided"), outs,
                      getstr(setup, "download"), getstr(setup, "measured"), getstr(d, "status_note"))
end

# Guessed hours per item, (low, high). Not measured: nobody has taken a course
# yet. The pilot (docs/COURSES_PLAN.md, Phase 6) measures real times, and until
# then everything that shows the estimate labels it as one.
const ESTIMATE_RATES = (unit = (0.5, 1.0), problem = (10 / 60, 25 / 60), guided = (2.0, 4.0), project = (4.0, 8.0))

"""
A course's time estimate from its counts: ready units, their practice
problems, guided projects and hole projects, at `ESTIMATE_RATES`. Returns
(low hours, high hours, basis), rounded out to whole hours; the basis says
what was counted and at what rate, so the number can be checked by hand.
"""
function time_estimate(c::CourseInfo, units::Vector{Unit})
    byid = Dict(u.id => u for u in units)
    ready = [byid[id] for id in c.units if haskey(byid, id) && byid[id].status == "ready"]
    n = (unit = length(ready), problem = sum(length(u.problems) for u in ready; init = 0),
         guided = length(c.guided), project = length(c.projects))
    r = ESTIMATE_RATES
    low = sum(n[k] * r[k][1] for k in keys(n))
    high = sum(n[k] * r[k][2] for k in keys(n))
    mins(h) = round(Int, 60h)
    basis = "$(mins(r.unit[1]))–$(mins(r.unit[2])) min per ready unit ($(n.unit)), " *
            "$(mins(r.problem[1]))–$(mins(r.problem[2])) min per practice problem ($(n.problem)), " *
            "$(Int(r.guided[1]))–$(Int(r.guided[2])) h per guided project ($(n.guided)), " *
            "$(Int(r.project[1]))–$(Int(r.project[2])) h per hole project ($(n.project)); " *
            "guessed rates, not measured"
    return floor(Int, low), ceil(Int, high), basis
end

"""All courses, in their declared order."""
load_courses(dir::String = COURSE_DIR) =
    sort!([load_course_info(joinpath(dir, "courses", f)) for f in readdir(joinpath(dir, "courses")) if endswith(f, ".toml")];
          by = c -> c.order)

"""The unit a prerequisite names: "scicomp/35-stiffness" -> "35-stiffness"."""
prereq_unit(p::AbstractString) = String(last(split(p, '/'; limit = 2)))
"""The course a prerequisite names explicitly, or `nothing` for a bare unit id."""
prereq_course(p::AbstractString) = occursin('/', p) ? String(first(split(p, '/'; limit = 2))) : nothing

"""unit id => course id."""
course_index(courses) = Dict(u => c.id for c in courses for u in c.units)

"""The course a unit belongs to (`nothing` if none)."""
course_of(courses, unit_id) = get(course_index(courses), unit_id, nothing)

"""Unit ids a unit depends on, directly or through other units."""
function prereq_closure(units::Vector{Unit}, id::AbstractString)
    pre = Dict(u.id => prereq_unit.(u.prerequisites) for u in units)
    seen = Set{String}(); stack = copy(get(pre, id, String[]))
    while !isempty(stack)
        p = pop!(stack); p in seen && continue
        push!(seen, p); append!(stack, get(pre, p, String[]))
    end
    return seen
end

"""A prerequisite cycle among the units, as a list of ids, or `nothing`."""
function prereq_cycle(units::Vector{Unit})
    pre = Dict(u.id => prereq_unit.(u.prerequisites) for u in units)
    state = Dict{String,Int}()            # 1 = on the current path, 2 = finished
    function visit(id, path)
        get(state, id, 0) == 2 && return nothing
        get(state, id, 0) == 1 && return [path[findfirst(==(id), path):end]; id]
        state[id] = 1
        for p in get(pre, id, String[])
            c = visit(p, [path; id]); c === nothing || return c
        end
        state[id] = 2
        return nothing
    end
    for u in units
        c = visit(u.id, String[]); c === nothing || return c
    end
    return nothing
end

"""Envs a course actually needs: its units' envs, its guided projects' envs, and base."""
function course_envs(c::CourseInfo, units::Vector{Unit}, guided_env::AbstractDict)
    byid = Dict(u.id => u for u in units)
    envs = Set(["base"])
    for id in c.units; haskey(byid, id) && push!(envs, byid[id].env); end
    for g in c.guided; haskey(guided_env, g) && push!(envs, guided_env[g]); end
    return sort!(collect(envs))
end

const PROJECTS_DIR = normpath(joinpath(@__DIR__, "..", "projects"))

"""Guided project name => env, from projects/guided/<p>/project.toml."""
function guided_envs(dir::String = joinpath(PROJECTS_DIR, "guided"))
    isdir(dir) || return Dict{String,String}()
    return Dict(p => String(get(TOML.parsefile(joinpath(dir, p, "project.toml")), "env", "base"))
                for p in readdir(dir) if isfile(joinpath(dir, p, "project.toml")))
end

"""Hole projects (projects/<p>/holes.toml)."""
hole_projects(dir::String = PROJECTS_DIR) =
    isdir(dir) ? [p for p in readdir(dir) if isfile(joinpath(dir, p, "holes.toml"))] : String[]

"""
Which course each entry of a learner's CLI state belongs to. Nothing in the
state is keyed by course (holes are "<project>/<hole>", lesson checks
"<lesson>/<check>", guided checks "<project>:<dir>", KCs are shared), so the
course split needs no rewrite of `.tutor/state.toml` or `.tutor/guided.toml`:
this maps the existing keys. Returns (course id => entry keys, unmapped keys).
"""
function state_by_course(state::AbstractDict, guided_state::AbstractDict, courses::Vector{CourseInfo},
                         units::Vector{Unit})
    cidx = course_index(courses)
    lesson_course = Dict(l => cidx[u.id] for u in units for l in u.lessons if haskey(cidx, u.id))
    project_course = Dict(p => c.id for c in courses for p in c.projects)
    guided_course = Dict(g => c.id for c in courses for g in c.guided)
    out = Dict(c.id => String[] for c in courses)
    unmapped = String[]
    put(c, k) = c === nothing ? push!(unmapped, k) : push!(out[c], k)
    for k in keys(get(state, "holes", Dict()))
        put(get(project_course, first(split(k, '/')), nothing), "holes/$k")
    end
    for k in keys(get(state, "items", Dict()))
        put(get(lesson_course, first(split(k, '/')), nothing), "items/$k")
    end
    for k in keys(get(guided_state, "projects", Dict()))
        put(get(guided_course, first(split(k, ':')), nothing), "guided/$k")
    end
    foreach(sort!, values(out))
    return out, sort!(unmapped)
end

"""
Structural checks across courses. Every unit belongs to exactly one course; a
prerequisite is in the same course (bare id) or names another course the
course requires ("<course>/<unit>"); no prerequisite cycle; each course's
`envs` is exactly what its units and guided projects use; every guided
project belongs to exactly one course. Returns a list of problems.
"""
function validate_courses(courses::Vector{CourseInfo}, units::Vector{Unit};
                          guided_env::AbstractDict = guided_envs(), projects = hole_projects())
    problems = String[]
    byid = Dict(u.id => u for u in units)
    cid = Dict(c.id => c for c in courses)
    length(cid) == length(courses) || push!(problems, "duplicate course id")
    allunique(c.order for c in courses) || push!(problems, "two courses share an order")
    owner = Dict{String,Vector{String}}()
    for c in courses, id in c.units
        push!(get!(owner, id, String[]), c.id)
    end
    for u in units
        cs = get(owner, u.id, String[])
        isempty(cs) && push!(problems, "$(u.id): belongs to no course")
        length(cs) > 1 && push!(problems, "$(u.id): belongs to more than one course ($(join(cs, ", ")))")
    end
    global_order = Dict(u.id => i for (i, u) in enumerate(units))
    for c in courses
        c.status in COURSE_STATUS || push!(problems, "course $(c.id): status must be one of $(COURSE_STATUS)")
        isempty(c.units) && push!(problems, "course $(c.id): no units")
        for id in c.units
            haskey(byid, id) || push!(problems, "course $(c.id): no unit $id")
        end
        known = filter(id -> haskey(byid, id), c.units)
        issorted(known; by = id -> global_order[id]) ||
            push!(problems, "course $(c.id): units must be listed in syllabus order")
        for r in c.requires
            haskey(cid, r) || (push!(problems, "course $(c.id): requires unknown course $r"); continue)
            cid[r].order < c.order || push!(problems, "course $(c.id): requires $r, which comes later")
        end
        for id in known, p in byid[id].prerequisites
            pc, pu = prereq_course(p), prereq_unit(p)
            if pc === nothing
                pu in c.units || push!(problems,
                    "$id: prerequisite $pu is not in course $(c.id); write it as \"<course>/$pu\"")
            elseif pc == c.id
                push!(problems, "$id: prerequisite $p is in the same course; write it as \"$pu\"")
            elseif !haskey(cid, pc)
                push!(problems, "$id: prerequisite $p names unknown course $pc")
            elseif !(pu in cid[pc].units)
                push!(problems, "$id: prerequisite $p: no unit $pu in course $pc")
            elseif !(pc in c.requires)
                push!(problems, "$id: prerequisite $p is in course $pc, which course $(c.id) does not require")
            end
        end
        want = course_envs(c, units, guided_env)
        sort(c.envs) == want ||
            push!(problems, "course $(c.id): envs must be exactly what its units and guided projects use: $(want)")
        for g in c.guided
            haskey(guided_env, g) || push!(problems, "course $(c.id): no guided project $g")
        end
        for p in c.projects
            p in projects || push!(problems, "course $(c.id): no project $p")
        end
        4 <= length(c.outcomes) <= 8 || push!(problems, "course $(c.id): needs 4 to 8 outcomes")
        # The landing page shows the download size; a size is shown only with where it was measured.
        c.status == "planned" || (!isempty(c.download) && !isempty(c.download_measured)) ||
            push!(problems, "course $(c.id): [setup] needs download and measured (where the size was measured)")
        # A course that is not ready says why, wherever its status is shown.
        c.status == "ready" || !isempty(strip(c.status_note)) ||
            push!(problems, "course $(c.id): status $(c.status) needs a status_note saying why")
        for (i, o) in enumerate(c.outcomes)
            isempty(o.assessed_by) && isempty(o.planned) &&
                push!(problems, "course $(c.id) outcome $i: nothing assesses it, not even a planned case")
            for a in o.assessed_by
                ok = startswith(a, "project:") ? a[9:end] in c.projects :
                     startswith(a, "guided:") ? a[8:end] in c.guided : a in c.units
                ok || push!(problems, "course $(c.id) outcome $i: '$a' is not a unit or project of this course")
            end
        end
    end
    for g in keys(guided_env)
        n = count(c -> g in c.guided, courses)
        n == 1 || push!(problems, "guided project $g belongs to $n courses (must be exactly 1)")
    end
    # Each course has its own sandbox image (src/runner.jl, `image_envs`), and
    # the environment picks the image, so an environment other than base may be
    # in one course only (a unit elsewhere would run in an image without it).
    for e in sort!(unique([e for c in courses for e in c.envs if e != "base"]))
        owners = [c.id for c in courses if e in c.envs]
        length(owners) == 1 ||
            push!(problems, "environment $e is used by courses $(join(owners, ", ")); each sandbox image holds one " *
                            "course's environments, so an environment other than base belongs to exactly one course")
    end
    cyc = prereq_cycle(units)
    cyc === nothing || push!(problems, "prerequisite cycle: $(join(cyc, " -> "))")
    return problems
end

"""Content-addressed key for an example's recorded output."""
example_key(code::AbstractString, mode::AbstractString = "repl") =
    bytes2hex(sha1((mode == "repl" ? "" : mode * ":") * strip(code)))[1:16]

outputs_path(u::Unit, dir::String = COURSE_DIR) = joinpath(dir, "outputs", u.id * ".toml")
"""Where `tutor course record` puts a unit's figures (PNG/SVG the examples produced)."""
figures_dir(u::Unit, dir::String = COURSE_DIR) = joinpath(dir, "outputs", "figures", u.id)
load_outputs(u::Unit, dir::String = COURSE_DIR) =
    (p = outputs_path(u, dir); isfile(p) ? TOML.parsefile(p) : Dict{String,Any}())

"""Project directory a unit's code runs in."""
env_dir(env::AbstractString, dir::String = COURSE_DIR) = joinpath(dir, "envs", env)

"""Packages listed in an environment's Project.toml."""
env_packages(env::AbstractString, dir::String = COURSE_DIR) =
    (f = joinpath(env_dir(env, dir), "Project.toml"); isfile(f) ? collect(keys(get(TOML.parsefile(f), "deps", Dict()))) : String[])

"""What is structurally wrong with a concept question (empty = nothing)."""
function question_problems(q::Question)
    out = String[]
    q.kind in ("choice", "output") || push!(out, "kind must be choice or output")
    isempty(strip(q.prompt)) && push!(out, "no prompt")
    2 <= length(q.choices) <= 6 || push!(out, "needs 2 to 6 choices")
    allunique(strip.(q.choices)) || push!(out, "choices must differ")
    1 <= q.answer <= length(q.choices) || return push!(out, "answer must index a choice (1-based)")
    isempty(strip(q.explain)) && push!(out, "no explanation")
    length(q.misconceptions) == length(q.choices) || return push!(out, "one misconception per choice (\"\" for the answer)")
    isempty(strip(q.misconceptions[q.answer])) || push!(out, "the right answer has a misconception")
    for (i, m) in enumerate(q.misconceptions)
        i != q.answer && isempty(strip(m)) && push!(out, "wrong choice $i has no misconception")
    end
    q.kind == "output" && isempty(strip(q.code)) && push!(out, "an output question needs code")
    return out
end

compile_measure(s) = isempty(s) ? nothing : try Regex(s) catch; nothing end

"""What is structurally wrong with an example's prediction (empty = nothing)."""
function prediction_problems(p::Prediction, e::Example, kcs)
    out = String[]
    p.kc in kcs || push!(out, "kc '$(p.kc)' is not one of the unit's kcs $(kcs)")
    isempty(strip(p.prompt)) && push!(out, "no prompt")
    isempty(strip(p.explain)) && push!(out, "no explanation")
    2 <= length(p.choices) <= 6 || push!(out, "needs 2 to 6 choices")
    allunique(strip.(p.choices)) || push!(out, "choices must differ")
    1 <= p.answer <= length(p.choices) || push!(out, "answer must index a choice (1-based)")
    # A key read from an output that is recorded but never compared could change unnoticed.
    e.check || push!(out, "the example has check = false: a prediction needs an output that verify compares")
    compile_measure(p.measure) === nothing && push!(out, "measure is not a regular expression")
    if isempty(p.ranges) == isempty(p.values)
        push!(out, "give either ranges (a numeric prediction) or values (a word prediction), not both or neither")
    elseif !isempty(p.ranges)
        length(p.ranges) == length(p.choices) || push!(out, "one range per choice")
        all(((lo, hi),) -> lo < hi, p.ranges) || push!(out, "each range is [lo, hi) with lo < hi")
        r = sort(p.ranges)
        all(i -> r[i][2] <= r[i+1][1], 1:length(r)-1) || push!(out, "ranges overlap: a value would select two choices")
    else
        length(p.values) == length(p.choices) || push!(out, "one value per choice")
        allunique(lowercase.(p.values)) || push!(out, "values must differ")
    end
    return out
end

"""
The choices a recorded output selects, and the text `measure` captured from it
(`nothing` if it does not match, or has no single capture group).
"""
function measured_choices(p::Prediction, output::AbstractString)
    re = compile_measure(p.measure)
    re === nothing && return (Int[], nothing)
    m = match(re, output)
    (m === nothing || length(m.captures) != 1 || m.captures[1] === nothing) && return (Int[], nothing)
    cap = String(m.captures[1])
    if !isempty(p.ranges)
        x = tryparse(Float64, cap)
        x === nothing && return (Int[], cap)
        return ([i for (i, (lo, hi)) in enumerate(p.ranges) if lo <= x < hi], cap)
    end
    return ([i for (i, v) in enumerate(p.values) if lowercase(v) == lowercase(cap)], cap)
end

"""
The key of each prediction is measured: in the recorded output (`rec`, as
`tutor course record` writes it), `measure` must capture a value that selects
exactly one choice, and that choice must be the declared `answer`.
"""
function prediction_key_problems(u::Unit, rec)
    out = String[]
    exs = get(rec, "examples", Dict())
    for s in u.sections, e in s.examples
        p = e.predict
        p === nothing && continue
        where = "$(u.id) '$(s.title)' prediction"
        r = get(exs, example_key(e.code, e.mode), nothing)
        r === nothing && (push!(out, "$where: its example has no recorded output"); continue)
        hold, cap = measured_choices(p, r["output"])
        if cap === nothing
            push!(out, "$where: `measure` does not match the recorded output with one capture group")
        elseif length(hold) != 1
            push!(out, "$where: the measured value $cap selects $(length(hold)) choices (exactly one must hold)")
        elseif only(hold) != p.answer
            push!(out, "$where: the measured value $cap selects choice $(only(hold)), but the answer is $(p.answer)")
        end
    end
    return out
end

"""Index of the capture group named `ok` in `re`, or 0."""
ok_group(re::Regex) = something(findfirst(==("ok"), Base.PCRE.capture_names(re.regex)), 0)
capture_count(re::Regex) = Int(Base.PCRE.info(re.regex, Base.PCRE.INFO_CAPTURECOUNT, UInt32))

"""What is structurally wrong with an example's method-choice checkpoint (empty = nothing)."""
function checkpoint_problems(c::Checkpoint, e::Example, kcs)
    out = String[]
    c.kc in kcs || push!(out, "kc '$(c.kc)' is not one of the unit's kcs $(kcs)")
    isempty(strip(c.prompt)) && push!(out, "no prompt")
    isempty(strip(c.explain)) && push!(out, "no explanation")
    isempty(strip(c.cost)) && push!(out, "no cost label (what the measured cost counts)")
    e.predict === nothing || push!(out, "an example carries a prediction or a checkpoint, not both")
    n = length(c.choices)
    2 <= n <= 6 || push!(out, "needs 2 to 6 choices")
    allunique(strip.(c.choices)) || push!(out, "choices must differ")
    length(c.rows) == n || push!(out, "one row regex per choice")
    for (i, r) in enumerate(c.rows)
        re = compile_measure(r)
        re === nothing && (push!(out, "row $i is not a regular expression"); continue)
        capture_count(re) - (ok_group(re) > 0) >= 1 || push!(out, "row $i has no capture group for the cost")
    end
    c.band > 1 || push!(out, "band must be greater than 1")
    isempty(c.good) && push!(out, "name the good choices (good = [...])")
    allunique(c.good) || push!(out, "good lists a choice twice")
    all(i -> 1 <= i <= n, c.good) || push!(out, "good must index choices (1-based)")
    length(unique(c.good)) < n || push!(out, "every choice is good: there is nothing to choose")
    length(c.misconceptions) == n || push!(out, "one misconception per choice (\"\" for a good one)")
    for (i, m) in enumerate(c.misconceptions)
        !(i in c.good) && isempty(strip(m)) && push!(out, "choice $i is not good and has no misconception")
    end
    return out
end

"""
The measured row of each choice in `output`: `(cost, ok)`, or `nothing` when
its regex does not match or a cost capture is not a number. `ok` is `true`
when the row has no `ok` group.
"""
function checkpoint_rows(c::Checkpoint, output::AbstractString)
    rows = Union{Nothing,Tuple{Float64,Bool}}[]
    for r in c.rows
        re = compile_measure(r)
        m = re === nothing ? nothing : match(re, output)
        m === nothing && (push!(rows, nothing); continue)
        k = ok_group(re)
        nums = [tryparse(Float64, x) for (j, x) in enumerate(m.captures) if j != k && x !== nothing]
        if isempty(nums) || any(isnothing, nums) || (k > 0 && m.captures[k] === nothing)
            push!(rows, nothing)
        else
            push!(rows, (sum(nums), k == 0 || lowercase(m.captures[k]) == "true"))
        end
    end
    return rows
end

"""
Score a checkpoint against an output: per choice its cost, whether it meets
the accuracy, its ratio to the cheapest choice that does, and its verdict
(`good`, `costly` or `fails`). Returns a String saying what is wrong when the
output cannot be scored.
"""
function score_checkpoint(c::Checkpoint, output::AbstractString)
    rows = checkpoint_rows(c, output)
    bad = findall(isnothing, rows)
    isempty(bad) || return "row $(join(bad, ", ")) does not match the output with a numeric cost"
    costs = [r[1] for r in rows]; oks = [r[2] for r in rows]
    any(oks) || return "no choice meets the accuracy (`ok` is false in every row)"
    best = minimum(costs[oks])
    best > 0 || return "the cheapest cost is $best: costs must be positive counts"
    ratios = costs ./ best
    verdicts = [!oks[i] ? "fails" : ratios[i] <= c.band ? "good" : "costly" for i in eachindex(costs)]
    return (; costs, oks, ratios, verdicts, good = findall(==("good"), verdicts))
end

"""
The key of each checkpoint is measured: in `rec` (a fresh `record` in verify,
the stored outputs in the fast tests and the site export) the good set must
equal `good`, and every ratio of a choice that meets the accuracy must lie at
least `CHOICE_MARGIN` away from the band's edge.
"""
function checkpoint_key_problems(u::Unit, rec)
    out = String[]
    exs = get(rec, "examples", Dict())
    for s in u.sections, e in s.examples
        c = e.choose
        c === nothing && continue
        where = "$(u.id) '$(s.title)' checkpoint"
        r = get(exs, example_key(e.code, e.mode), nothing)
        r === nothing && (push!(out, "$where: its example has no recorded output"); continue)
        append!(out, ["$where: $m" for m in checkpoint_output_problems(c, r["output"])])
    end
    return out
end

"""Why `output` does not support the checkpoint's declared verdicts (empty = it does)."""
function checkpoint_output_problems(c::Checkpoint, output::AbstractString)
    sc = score_checkpoint(c, output)
    sc isa String && return [sc]
    out = String[]
    sort(sc.good) == sort(c.good) ||
        push!(out, "the measurements make choice(s) $(sc.good) good, but good = $(sort(c.good))")
    for i in eachindex(sc.ratios)
        sc.oks[i] || continue
        x = sc.ratios[i]
        c.band / CHOICE_MARGIN < x < c.band * CHOICE_MARGIN &&
            push!(out, "choice $i costs $(round(x; sigdigits = 3)) times the cheapest, within a factor $CHOICE_MARGIN " *
                       "of the band ($(c.band)): a small drift in the counts could flip its verdict")
    end
    return out
end

has_group(re::Regex, name) = name in values(Base.PCRE.capture_names(re.regex))

"""What is structurally wrong with an example's break-it challenge (empty = nothing)."""
function breakit_problems(b::BreakIt, e::Example, kcs)
    out = String[]
    b.kc in kcs || push!(out, "kc '$(b.kc)' is not one of the unit's kcs $(kcs)")
    for (f, what) in ((b.prompt, "prompt"), (b.explain, "explanation"), (b.param, "param (the parameter's name)"),
                      (b.measure, "measure (what the row's number is)"), (b.short, "short (feedback where the method still works)"),
                      (b.past, "past (feedback well past the edge)"))
        isempty(strip(f)) && push!(out, "no $what")
    end
    # The edge is read from the output; an output verify does not compare could move it unnoticed.
    e.check || push!(out, "the example has check = false: a break-it sweep needs an output that verify compares")
    (e.predict === nothing && e.choose === nothing) ||
        push!(out, "an example carries one of a prediction, a checkpoint or a break-it challenge")
    re = compile_measure(b.row)
    if re === nothing
        push!(out, "row is not a regular expression")
    elseif !(has_group(re, "p") && has_group(re, "m"))
        push!(out, "row needs named groups `p` (the parameter) and `m` (the measurement)")
    end
    b.fails in ("above", "below") || push!(out, "fails must be \"above\" or \"below\"")
    isfinite(b.limit) || push!(out, "limit must be a finite number")
    1 < b.close <= 2 || push!(out, "close must be in (1, 2]")
    lo, hi = b.edge
    if !(isfinite(lo) && isfinite(hi) && 0 < lo < hi)
        push!(out, "edge is [low, high] with 0 < low < high")
    elseif hi / lo > b.close
        push!(out, "the edge spans a factor $(round(hi / lo; sigdigits = 3)), wider than close = $(b.close): sweep more finely near it")
    end
    occursin("{{p}}", b.probe) || push!(out, "probe must contain {{p}} where the parameter's value goes")
    return out
end

"""The `(p, m)` pairs of every line that `row` matches, or `nothing` if a matched value is not a number."""
function breakit_rows(b::BreakIt, output::AbstractString)
    re = compile_measure(b.row)
    re === nothing && return nothing
    rows = Tuple{Float64,Float64}[]
    for line in eachline(IOBuffer(output))
        m = match(re, line)
        m === nothing && continue
        p, x = tryparse(Float64, something(m["p"], "")), tryparse(Float64, something(m["m"], ""))
        (p === nothing || x === nothing) && return nothing
        push!(rows, (p, x))
    end
    return rows
end

"""Whether the method failed at a row whose measurement is `m` (NaN counts as failed: the run broke down)."""
breakit_failed(b::BreakIt, m::Real) = isnan(m) || (b.fails == "above" ? m > b.limit : m < b.limit)

"""
Read a break-it sweep from an output: the rows sorted by the parameter,
whether each failed, the measured edge and the side that fails (`"high"`:
values above the edge fail). Returns a String saying what is wrong when the
output has no single edge.
"""
function score_breakit(b::BreakIt, output::AbstractString)
    rows = breakit_rows(b, output)
    rows === nothing && return "a row matched with a value that is not a number"
    length(rows) >= BREAK_MIN_ROWS || return "the sweep has $(length(rows)) rows (at least $BREAK_MIN_ROWS needed)"
    ps = first.(rows)
    all(p -> isfinite(p) && p > 0, ps) || return "every swept value must be a positive number"
    allunique(ps) || return "a value is swept twice"
    rows = sort(rows)
    ps, ms = first.(rows), last.(rows)
    failed = [breakit_failed(b, m) for m in ms]
    all(failed) && return "the method fails at every swept value: there is no edge in the sweep"
    any(failed) || return "the method works at every swept value: there is no edge in the sweep"
    changes = findall(i -> failed[i] != failed[i+1], 1:length(failed)-1)
    length(changes) == 1 ||
        return "the method changes between working and failing $(length(changes)) times along the sweep: there is no single edge"
    i = only(changes)
    return (; ps, ms, failed, edge = (ps[i], ps[i+1]), side = failed[end] ? "high" : "low")
end

"""Why `output` does not support the challenge's declared edge (empty = it does)."""
function breakit_output_problems(b::BreakIt, output::AbstractString)
    sc = score_breakit(b, output)
    sc isa String && return [sc]
    all(isapprox.(sc.edge, b.edge; rtol = 1e-9)) && return String[]
    return ["the sweep changes between $(sc.edge[1]) and $(sc.edge[2]), but edge = [$(b.edge[1]), $(b.edge[2])]"]
end

"""Break-it edges are measured: in `rec`, each sweep must have one edge, the declared one."""
function breakit_key_problems(u::Unit, rec)
    out = String[]
    exs = get(rec, "examples", Dict())
    for s in u.sections, e in s.examples
        b = e.breakit
        b === nothing && continue
        where = "$(u.id) '$(s.title)' break-it"
        r = get(exs, example_key(e.code, e.mode), nothing)
        r === nothing && (push!(out, "$where: its example has no recorded output"); continue)
        append!(out, ["$where: $m" for m in breakit_output_problems(b, r["output"])])
    end
    return out
end

"""The probe's code at value `x` (written as Julia reads it back: `repr`)."""
probe_code(b::BreakIt, x::Float64) = replace(b.probe, "{{p}}" => repr(x))

"""
Why the probe's outputs at the edge's two ends disagree with the sweep (empty
= they agree): each must print one `row` line, and the method must work at
the end on its working side and fail at the other.
"""
function probe_problems(b::BreakIt, side::AbstractString, out_lo::AbstractString, out_hi::AbstractString)
    out = String[]
    for (x, o, should_fail) in ((b.edge[1], out_lo, side == "low"), (b.edge[2], out_hi, side == "high"))
        rows = breakit_rows(b, o)
        if rows === nothing || length(rows) != 1
            push!(out, "the probe at $x prints $(rows === nothing ? "a row that is not a number" : "$(length(rows)) rows") (one is needed):\n$o")
        elseif breakit_failed(b, only(rows)[2]) != should_fail
            push!(out, "the probe at $x $(should_fail ? "works" : "fails"), but the sweep says it $(should_fail ? "fails" : "works") there")
        end
    end
    return out
end

"""What is structurally wrong with an example's explorer (empty = nothing); the grid itself is checked on the output."""
function explorer_problems(x::Explorer, e::Example, kcs)
    out = String[]
    x.kc in kcs || push!(out, "kc '$(x.kc)' is not one of the unit's kcs $(kcs)")
    for (f, what) in ((x.prompt, "prompt"), (x.explain, "explanation"), (x.label, "label (what the measure is)"))
        isempty(strip(f)) && push!(out, "no $what")
    end
    # The grid is read from the output; an output verify does not compare could change unnoticed.
    e.check || push!(out, "the example has check = false: an explorer's grid needs an output that verify compares")
    (e.choose === nothing && e.breakit === nothing) ||
        push!(out, "an example with an explorer carries no checkpoint or break-it challenge (both hide the output)")
    groups = [a.group for a in x.axes]
    1 <= length(x.axes) <= EXPLORE_MAX_AXES || push!(out, "an explorer has 1 to $EXPLORE_MAX_AXES axes")
    allunique(groups) || push!(out, "an axis is named twice")
    any(a -> isempty(strip(a.label)), x.axes) && push!(out, "every axis needs a label")
    x.measure in groups && push!(out, "the measure '$(x.measure)' is also an axis")
    x.x in groups || push!(out, "x = '$(x.x)' is not one of the axes $(groups)")
    isempty(x.series) || (x.series in groups && x.series != x.x) ||
        push!(out, "series = '$(x.series)' must be an axis other than x (or left out)")
    re = compile_measure(x.row)
    if re === nothing
        push!(out, "row is not a regular expression")
    else
        for g in vcat(groups, x.measure)
            has_group(re, g) || push!(out, "row has no named group `$g`")
        end
    end
    return out
end

"""
Read an explorer's grid from an output: per axis, its values (numbers sorted
ascending, or words in the order they first appear) with the text as
printed, and the measure at every point as printed, in row-major order over
the axes (the last axis varies fastest). Returns a String saying what is
wrong when the matched lines are not a full grid.
"""
function explorer_grid(x::Explorer, output::AbstractString)
    re = compile_measure(x.row)
    re === nothing && return "row is not a regular expression"
    pts = Tuple{Vector{String},String}[]
    for line in eachline(IOBuffer(output))
        m = match(re, line)
        m === nothing && continue
        cs = [something(m[a.group], "") for a in x.axes]
        v = something(m[x.measure], "")
        tryparse(Float64, v) === nothing && return "the measure '$v' is not a number: $line"
        push!(pts, (cs, v))
    end
    isempty(pts) && return "no output line matches row"
    axes = Any[]
    for (k, a) in enumerate(x.axes)
        texts = unique(p[1][k] for p in pts)
        nums = tryparse.(Float64, texts)
        numeric = all(n -> n !== nothing && isfinite(n), nums)
        if numeric
            allunique(nums) || return "axis $(a.group) prints one value two ways: $(texts)"
            order = sortperm(nums)
            texts, nums = texts[order], Float64.(nums[order])
        end
        length(texts) >= 2 || return "axis $(a.group) has one value: a slider needs at least 2"
        a.group == x.x && !numeric && return "the x axis $(a.group) must be numbers: $(texts)"
        a.group == x.x && length(texts) < 3 && return "the x axis $(a.group) has $(length(texts)) values (at least 3 make a line)"
        a.log && !(numeric && all(>(0), nums)) && return "axis $(a.group) is on a log scale, so its values must be positive numbers"
        push!(axes, (; group = a.group, label = a.label, log = a.log, numeric, texts, nums = numeric ? nums : Float64[]))
    end
    shape = [length(a.texts) for a in axes]
    prod(shape) <= EXPLORE_MAX_POINTS || return "the grid has $(prod(shape)) points (at most $EXPLORE_MAX_POINTS)"
    cells = fill("", shape...)
    for (cs, v) in pts
        ix = [findfirst(==(c), a.texts) for (c, a) in zip(cs, axes)]
        isempty(cells[ix...]) || return "the point $(join(cs, ", ")) is printed twice"
        cells[ix...] = v
    end
    missing_at = findfirst(isempty, cells)
    missing_at === nothing ||
        return "the grid is not full: nothing printed at $(join([a.texts[i] for (a, i) in zip(axes, Tuple(missing_at))], ", "))"
    if x.log
        vals = parse.(Float64, vec(cells))
        any(v -> v < 0, vals) && return "the measure is on a log scale but a value is negative"
    end
    # row-major: the last axis varies fastest (Julia's arrays are column-major, so permute)
    values = vec(permutedims(cells, reverse(1:length(shape))))
    return (; axes, values)
end

"""Explorer grids are measured: in `rec`, each explorer's example output must be a full grid."""
function explorer_key_problems(u::Unit, rec)
    out = String[]
    exs = get(rec, "examples", Dict())
    for s in u.sections, e in s.examples
        x = e.explore
        x === nothing && continue
        where = "$(u.id) '$(s.title)' explorer"
        r = get(exs, example_key(e.code, e.mode), nothing)
        r === nothing && (push!(out, "$where: its example has no recorded output"); continue)
        g = explorer_grid(x, r["output"])
        g isa String && push!(out, "$where: $g")
    end
    return out
end

# Phrases that carry no information in teaching prose (marketing words, filler
# transitions, chatbot openers). The course says what a thing does and shows
# it; `prose_problems` keeps that mechanical. Matched case-insensitively on
# word boundaries, in prose only (not in code).
const FILLER = [
    "delve", "seamless", "seamlessly", "leverage", "leverages", "leveraging", "robust", "powerful",
    "cutting-edge", "state-of-the-art", "game-changer", "game-changing", "unlock", "unlocks",
    "empower", "empowers", "revolutionize", "revolutionizes", "supercharge", "effortless",
    "effortlessly", "elevate", "harness", "dive into", "deep dive", "in today's", "worth noting",
    "let's", "embark", "journey", "plethora", "myriad", "tapestry", "landscape", "a testament",
    "boasts", "rich ecosystem", "blazing", "lightning-fast", "best-in-class", "world-class",
    "at its core", "whether you're", "look no further", "the power of", "simply put",
    "in conclusion", "crucial", "vital", "realm", "furthermore", "moreover", "additionally",
    "comprehensive", "cornerstone", "showcase", "showcases", "streamline", "streamlined",
    "intuitive", "elegant", "elegantly", "magic", "magical", "out of the box", "under the hood",
    "a wide range", "a variety of", "in summary", "ultimately", "notably", "truly",
    # self-praise and padding found in review (unit 21 to 28 drafts)
    "honest", "honestly", "and friends", "handy", "cheap insurance", "friendlier", "a good first try",
    "makes it easy", "easy to", "note that", "simply", "importantly", "essentially", "basically",
    "straightforward", "of course", "it's worth", "a breeze",
]

# A choice question whose answer is the one longest option can be answered
# without reading it: drafts tend to write a careful, qualified key next to
# short strawmen. Per unit, at most this share of choice questions may have
# the answer as the unique longest choice (with 3 or 4 options and lengths
# unrelated to correctness, about a third would by chance).
const MAX_LONGEST_ANSWER_SHARE = 0.4

"""Choice questions that give the answer away by length (see `MAX_LONGEST_ANSWER_SHARE`)."""
function question_balance_problems(u::Unit)
    qs = [q for q in questions(u) if q.kind == "choice"]
    length(qs) < 4 && return String[]
    # Both ends: overcorrecting (terse keys beside long distractors) is the same tell.
    unique_extreme(q, ext) = (L = length.(q.choices); L[q.answer] == ext(L) && count(==(ext(L)), L) == 1)
    limit = floor(Int, MAX_LONGEST_ANSWER_SHARE * length(qs))
    out = String[]
    for (ext, word, fix) in ((maximum, "longest", "shorten the key to its claim (the reason goes in `explain`) and make distractors as specific"),
                             (minimum, "shortest", "give the key the same detail as the distractors"))
        tells = filter(q -> unique_extreme(q, ext), qs)
        length(tells) <= limit && continue
        push!(out, "$(u.id): in $(length(tells)) of $(length(qs)) choice questions the answer is the $word choice " *
                   "(at most $limit allowed): $fix; e.g. \"$(first(first(tells).prompt, 60))\"")
    end
    return out
end

"""Learner-facing prose of a unit (no code), as (where, text) pairs."""
function unit_prose(u::Unit)
    out = Tuple{String,String}[("summary", u.summary)]
    for s in u.sections
        push!(out, ("'$(s.title)'", s.title * "\n" * strip_code(s.body)))
        append!(out, [("'$(s.title)' analogy", strip_code(join([a.title, a.text, a.breaks], "\n"))) for a in s.analogies])
        append!(out, [("'$(s.title)' diagram", strip_code(g.alt * "\n" * g.caption)) for g in s.diagrams])
        append!(out, [("'$(s.title)' caption", e.caption * "\n" * e.notice) for e in s.examples])
        for e in s.examples
            p = e.predict
            p === nothing && continue
            push!(out, ("'$(s.title)' prediction", strip_code(join(vcat(p.prompt, p.choices, p.explain), "\n"))))
        end
        for e in s.examples
            c = e.choose
            c === nothing && continue
            push!(out, ("'$(s.title)' checkpoint",
                        strip_code(join(vcat(c.prompt, c.choices, c.cost, c.explain, c.misconceptions), "\n"))))
        end
        for e in s.examples
            b = e.breakit
            b === nothing && continue
            push!(out, ("'$(s.title)' break-it", strip_code(join([b.prompt, b.measure, b.explain, b.short, b.past], "\n"))))
        end
        for e in s.examples
            x = e.explore
            x === nothing && continue
            push!(out, ("'$(s.title)' explorer",
                        strip_code(join(vcat(x.prompt, x.label, x.explain, [a.label for a in x.axes]), "\n"))))
        end
        for q in s.questions
            txt = join(vcat(q.prompt, q.explain, q.misconceptions, q.kind == "choice" ? q.choices : String[]), "\n")
            push!(out, ("'$(s.title)' question", strip_code(txt)))
        end
    end
    append!(out, [("reference $(r.id)", r.note) for r in u.references])
    for p in u.problems
        push!(out, (p.id, strip_code(join(vcat(p.title, p.prompt, p.hints, [v.label for v in p.variants]), "\n"))))
        b = p.bug
        b === nothing ||
            push!(out, ("$(p.id) find the bug", strip_code(join(vcat(b.misconception, [t.name for t in b.tests],
                                                                     [t.explain for t in b.tests]), "\n"))))
        z = p.parsons
        z === nothing || push!(out, ("$(p.id) Parsons", strip_code(join([d.misconception for d in z.distractors], "\n"))))
    end
    return out
end

# Fenced blocks and inline code are code, not prose.
strip_code(s) = replace(replace(s, r"```.*?```"s => " "), r"`[^`\n]*`" => " ")

"""Filler phrases and em dashes in a unit's prose (empty = clean)."""
function prose_problems(u::Unit)
    out = String[]
    for (where, txt) in unit_prose(u)
        low = lowercase(txt)
        for w in FILLER
            occursin(Regex("(?<![\\w-])\\Q" * w * "\\E(?![\\w-])"), low) &&
                push!(out, "$(u.id) $where: filler phrase \"$w\"")
        end
        occursin('—', txt) && push!(out, "$(u.id) $where: em dash (use a colon, comma or parentheses)")
    end
    return out
end

"""Where a unit's hand-drawn diagrams live."""
diagrams_dir(u::Unit, dir::String = COURSE_DIR) = joinpath(dir, "diagrams", u.id)

# An SVG diagram is shown with <img>, which never runs its scripts, but the file
# is also served as-is: refuse anything active or anything fetched from elsewhere.
const SVG_FORBIDDEN = [r"<script"i, r"<foreignObject"i, r"\son\w+\s*="i, r"(href|src)\s*=\s*[\"'](?!#)"i,
                       r"javascript:"i, r"<image"i, r"@import"i, r"url\(\s*[\"']?(?!#)"i, r"<!ENTITY"i]

"""Problems in an SVG diagram's text (empty when it is safe to serve and shows something)."""
function svg_problems(txt::AbstractString)
    out = String[]
    occursin(r"<svg[\s>]", txt) || push!(out, "not an SVG document")
    occursin(r"viewBox\s*="i, txt) || push!(out, "no viewBox (it must scale to the column)")
    occursin(r"<title[\s>]", txt) || push!(out, "no <title> element")
    for r in SVG_FORBIDDEN
        occursin(r, txt) && push!(out, "contains $(r.pattern) (no scripts, handlers, external links or images)")
    end
    sizeof(txt) <= 64_000 || push!(out, "larger than 64 kB")
    # A browser shows nothing for an SVG that is not well-formed XML. Catch the
    # two slips hand-written text makes: a bare `<` (write `&lt;`) and a bare
    # `&` (write `&amp;`).
    for m in eachmatch(r"<(?![A-Za-z/!?])", txt)
        push!(out, "bare '<' at byte $(m.offset) (not well-formed XML; write &lt;)")
    end
    for m in eachmatch(r"&(?!(?:[A-Za-z][A-Za-z0-9]*|#[0-9]+|#x[0-9A-Fa-f]+);)", txt)
        push!(out, "bare '&' at byte $(m.offset) (not well-formed XML; write &amp;)")
    end
    return out
end

const REF_ID = r"^[a-z][a-z0-9-]*$"

"""Checks on a unit's analogies, diagrams and references (Phase 5b)."""
function enrichment_problems(u::Unit, dir::String = COURSE_DIR)
    out = String[]
    ids = [r.id for r in u.references]
    for r in u.references
        occursin(REF_ID, r.id) || push!(out, "$(u.id) reference '$(r.id)': id must be lowercase kebab-case")
        count(==(r.id), ids) == 1 || push!(out, "$(u.id) reference '$(r.id)': duplicate id")
        for (k, v) in (("authors", r.authors), ("title", r.title), ("venue", r.venue), ("note", r.note))
            isempty(strip(v)) && push!(out, "$(u.id) reference '$(r.id)': no $k")
        end
        1600 <= r.year <= 2100 || push!(out, "$(u.id) reference '$(r.id)': year must be given")
        occursin(r"^https://[^\s]+$", r.url) || push!(out, "$(u.id) reference '$(r.id)': url must be a public https link")
        any(s -> r.id in s.refs, u.sections) || push!(out, "$(u.id) reference '$(r.id)': no section cites it")
    end
    files = String[]
    for s in u.sections
        for id in s.refs
            id in ids || push!(out, "$(u.id) '$(s.title)': cites '$id', which is not in the unit's references")
        end
        for a in s.analogies
            isempty(strip(a.text)) && push!(out, "$(u.id) '$(s.title)' analogy: no text")
            length(strip(a.breaks)) >= 20 ||
                push!(out, "$(u.id) '$(s.title)' analogy: say where it breaks down (`breaks`, a sentence or more)")
        end
        for g in s.diagrams
            push!(files, g.file)
            occursin(r"^[a-z0-9][a-z0-9-]*\.svg$", g.file) ||
                push!(out, "$(u.id) '$(s.title)' diagram: file must be a kebab-case .svg name")
            length(strip(g.alt)) >= 40 ||
                push!(out, "$(u.id) '$(s.title)' diagram $(g.file): alt text must describe the picture (40+ characters)")
            path = joinpath(diagrams_dir(u, dir), g.file)
            if isfile(path)
                append!(out, ["$(u.id) diagram $(g.file): $m" for m in svg_problems(read(path, String))])
            else
                push!(out, "$(u.id) diagram $(g.file): no file course/diagrams/$(u.id)/$(g.file)")
            end
        end
    end
    allunique(files) || push!(out, "$(u.id): a diagram is used twice")
    d = diagrams_dir(u, dir)
    for f in (isdir(d) ? readdir(d) : String[])
        f in files || push!(out, "$(u.id): course/diagrams/$(u.id)/$f is not used by any section")
    end
    return out
end

"""Structural checks that need no Julia run. Returns a list of problems."""
function validate_course(units::Vector{Unit}; dir::String = COURSE_DIR, strict::Bool = true,
                         lesson_ids = [splitext(f)[1] for f in readdir(joinpath(dir, "..", "lessons")) if endswith(f, ".toml")])
    problems = String[]
    ids = Set{String}()
    pids = Set{String}()
    seen_order = String[]
    for u in units
        u.id in ids && push!(problems, "$(u.id): duplicate unit id")
        push!(ids, u.id)
        u.track in TRACKS || push!(problems, "$(u.id): track '$(u.track)' is not one of $(TRACKS)")
        u.status in ("ready", "planned") || push!(problems, "$(u.id): status must be ready or planned")
        isdir(env_dir(u.env, dir)) || push!(problems, "$(u.id): no environment course/envs/$(u.env)")
        for pre in prereq_unit.(u.prerequisites)
            pre in seen_order || (!strict && !any(v -> v.id == pre, units)) ||
                push!(problems, "$(u.id): prerequisite $pre is not an earlier unit")
        end
        for l in u.lessons
            l in lesson_ids || push!(problems, "$(u.id): no lesson $l")
        end
        if haskey(TRACK_REQUIRES, u.track)
            isempty(u.prerequisites) &&
                push!(problems, "$(u.id): a unit of the $(u.track) track must name the earlier units it builds on")
            for v in units
                v.track in TRACK_REQUIRES[u.track] && !(v.id in seen_order) &&
                    push!(problems, "$(u.id): the $(u.track) track assumes $(v.id), which must come before it")
            end
        end
        push!(seen_order, u.id)
        if u.status == "planned"
            isempty(u.outline) && push!(problems, "$(u.id): a planned unit needs an outline")
            continue
        end
        isempty(u.sections) && push!(problems, "$(u.id): no sections")
        append!(problems, prose_problems(u))
        append!(problems, enrichment_problems(u, dir))
        append!(problems, question_balance_problems(u))
        for s in u.sections, e in s.examples
            isempty(strip(e.code)) && push!(problems, "$(u.id): empty example in '$(s.title)'")
            e.mode in ("repl", "file") || push!(problems, "$(u.id): example mode must be repl or file")
            e.predict === nothing ||
                append!(problems, ["$(u.id) '$(s.title)' prediction: $m" for m in prediction_problems(e.predict, e, u.kcs)])
            e.choose === nothing ||
                append!(problems, ["$(u.id) '$(s.title)' checkpoint: $m" for m in checkpoint_problems(e.choose, e, u.kcs)])
            e.breakit === nothing ||
                append!(problems, ["$(u.id) '$(s.title)' break-it: $m" for m in breakit_problems(e.breakit, e, u.kcs)])
            e.explore === nothing ||
                append!(problems, ["$(u.id) '$(s.title)' explorer: $m" for m in explorer_problems(e.explore, e, u.kcs)])
        end
        for s in u.sections, (i, q) in enumerate(s.questions)
            append!(problems, ["$(u.id) '$(s.title)' question $i: $m" for m in question_problems(q)])
        end
        for p in u.problems
            p.id in pids && push!(problems, "$(p.id): duplicate problem id")
            push!(pids, p.id)
            p.difficulty in DIFFICULTIES || push!(problems, "$(p.id): difficulty must be one of $(DIFFICULTIES)")
            p.compare in ("isequal", "isapprox", "custom") ||
                push!(problems, "$(p.id): compare must be isequal, isapprox or custom")
            (p.compare == "custom") == !isempty(strip(p.checker)) ||
                push!(problems, "$(p.id): a `checker` is required with compare = \"custom\" and only then")
            for pkg in p.packages
                pkg in env_packages(u.env) || push!(problems, "$(p.id): package $pkg is not in course/envs/$(u.env)")
            end
            isempty(p.cases) && isempty(p.gen) && push!(problems, "$(p.id): no test cases")
            Base.isidentifier(p.entry) || push!(problems, "$(p.id): entry '$(p.entry)' is not an identifier")
            # Escaped, and bounded by "not an identifier character" on both
            # sides: `\b` never matches after the `!` of `normalize!(`.
            occursin(Regex("(?<![\\w!])\\Q" * p.entry * "\\E(?![\\w!])"), p.starter) ||
                push!(problems, "$(p.id): starter does not mention $(p.entry)")
            if p.perf !== nothing
                length(p.perf.sizes) in (1, 2) && issorted(p.perf.sizes; lt = <=) ||
                    push!(problems, "$(p.id): perf.sizes must be one size, or two increasing sizes (two give a growth estimate)")
            end
            1 <= p.threads <= 16 || push!(problems, "$(p.id): threads must be 1 to 16")
            1 <= p.repeats <= 100 || push!(problems, "$(p.id): repeats must be 1 to 100")
            isempty(p.variants) && push!(problems, "$(p.id): no variants (the grader's own tests)")
            any(v -> "incorrect" in v.expect, p.variants) ||
                push!(problems, "$(p.id): needs at least one variant expected to be incorrect")
            for v in p.variants, x in v.expect
                x in VARIANT_EXPECT || push!(problems, "$(p.id)/$(v.label): unknown expectation '$x'")
            end
            p.bug === nothing || append!(problems, ["$(p.id) find the bug: $m" for m in bug_problems(p, u.kcs)])
            p.parsons === nothing || append!(problems, ["$(p.id) Parsons: $m" for m in parsons_problems(p, u.kcs)])
            p.bug !== nothing && p.parsons !== nothing && push!(problems, "$(p.id): a problem is find-the-bug or Parsons, not both")
        end
    end
    return problems
end

end # module Course
