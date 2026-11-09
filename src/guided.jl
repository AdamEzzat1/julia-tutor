# Guided build projects (docs/GUIDED.md): the student writes the package and
# its tests from a milestone spec; the tutor checks the code against hidden
# acceptance tests and the tests against the reference and seeded mutants of
# it.
#
# Everything that runs student code goes through `Practice.child` (the sandbox
# container with `Runner.SANDBOX[] === :docker`, else a plain process for the
# learner's own code on their own machine), with a generated driver
# (src/guided_driver.jl) as the program. This module only reads the student's
# files as text, runs the static checker on them (which never executes them),
# and turns the driver's result into feedback with `assess`, a pure function.

module Guided

using TOML, Base64
using ..Runner, ..Course, ..Checker, ..Practice

export load_guided, load_all, check, assess, format_check, verify_project

const GUIDED_DIR = normpath(joinpath(@__DIR__, "..", "projects", "guided"))
const DRIVER = joinpath(@__DIR__, "guided_driver.jl")
const SEED = 20261108
# Environments whose packages load in a plain process on every host (see
# CLAUDE.md, Known gaps: the others hit the Windows path-length limit).
const HOST_ENVS = ("base", "data", "calculus", "python")
const DEFAULT_MIN_SCORE = 0.75
const MAX_FILES = 200
const MAX_BYTES = 2_000_000
const STAGE = "<<<guided-stage>>>"
const MAX_TEST_ADVICE = 3      # behaviours whose "what to test" advice one check shows

# ---- the format ----------------------------------------------------------------------

struct Behaviour
    id::String
    kc::String
    spec::String                   # what correct code does, in prose (shown on failure)
    hints::Vector{String}          # 3 levels; level 1 names the idea
    answer_tokens::Vector{String}  # fragments level-1 hints must not contain
    test_hints::Vector{String}     # 3 levels: what a test for this behaviour checks
end

struct Api
    signature::String
    doc::String
end

"""
A milestone's `[milestone.perf]`: one entry function of the student's package
graded by `Practice.grade` (correctness on `cases`, then speed, allocations,
growth and type stability relative to the reference at `sizes`).
"""
struct PerfSpec
    entry::String
    cases::Vector{String}          # argument lists as source
    args::String                   # perf arguments, with `rng` and `n` in scope
    sizes::Vector{Int}
    mutates::Bool
    compare::String                # "isequal" or "isapprox"
    rtol::Float64
    required::Bool                 # false: reported, never blocks
    fail_on::Vector{String}        # Practice verdicts that block when required
end

const PERF_FAIL_ON = ["slow", "allocates", "scaling", "unstable"]

struct Milestone
    id::Int
    title::String
    goal::String
    api::Vector{Api}
    behaviours::Vector{Behaviour}
    must_cover::Vector{String}
    min_score::Float64
    questions::Vector{Course.Question}
    perf::Union{Nothing,PerfSpec}
end

struct Mutant
    id::String
    milestone::Int
    behaviour::String
    file::String                   # relative to reference/
    find::String
    replace::String
end

struct Fixture
    name::String
    milestone::Int
    expect::Vector{String}         # verdicts the check must give
end

struct GuidedProject
    name::String
    dir::String
    package::String
    env::String
    status::String                 # "ready" or "planned"
    title::String
    summary::String
    kcs::Vector{String}
    reading::String
    milestones::Vector{Milestone}
    mutants::Vector{Mutant}
    fixtures::Vector{Fixture}
end

strs(d, k) = String.(get(d, k, String[]))

function load_behaviour(d)
    Behaviour(Course.getstr(d, "id"), Course.getstr(d, "kc"), Course.getstr(d, "spec"), strs(d, "hints"),
              strs(d, "answer_tokens"), strs(d, "test_hints"))
end

function load_milestone(d)
    Milestone(Int(d["id"]), Course.getstr(d, "title"), Course.getstr(d, "goal"),
              [Api(Course.getstr(a, "signature"), Course.getstr(a, "doc")) for a in get(d, "api", Any[])],
              [load_behaviour(b) for b in get(d, "behaviour", Any[])], strs(d, "must_cover"),
              Float64(get(d, "min_score", DEFAULT_MIN_SCORE)),
              [Course.load_question(q) for q in get(d, "question", Any[])],
              haskey(d, "perf") ? load_perf(d["perf"]) : nothing)
end

load_perf(d) = PerfSpec(Course.getstr(d, "entry"), strs(d, "cases"), Course.getstr(d, "args"), Int.(get(d, "sizes", Int[])),
                        get(d, "mutates", false), Course.getstr(d, "compare", "isapprox"), Float64(get(d, "rtol", 1e-8)),
                        get(d, "required", true), String.(get(d, "fail_on", PERF_FAIL_ON)))

"""Load `projects/guided/<name>/` (project.toml, mutants.toml, fixtures.toml)."""
function load_guided(name::AbstractString; root::String = GUIDED_DIR)
    # The name can come from a student's `.guided` file: a plain directory name only.
    occursin(r"^[a-z][a-z0-9_-]*$", name) || error("not a guided project name: $(repr(name))")
    dir = joinpath(root, name)
    isfile(joinpath(dir, "project.toml")) || error("no guided project `$name` (tutor guided list)")
    d = Course.normalize_nl(TOML.parsefile(joinpath(dir, "project.toml")))
    mf = joinpath(dir, "mutants.toml")
    md = isfile(mf) ? Course.normalize_nl(TOML.parsefile(mf)) : Dict{String,Any}()
    mutants = [Mutant(Course.getstr(m, "id"), Int(m["milestone"]), Course.getstr(m, "behaviour"),
                      Course.getstr(m, "file"), Course.getstr(m, "find"), Course.getstr(m, "replace"))
               for m in get(md, "mutant", Any[])]
    ff = joinpath(dir, "fixtures.toml")
    fd = isfile(ff) ? TOML.parsefile(ff) : Dict{String,Any}()
    fixtures = [Fixture(Course.getstr(f, "name"), Int(f["milestone"]), strs(f, "expect"))
                for f in get(fd, "fixture", Any[])]
    ms = sort!([load_milestone(m) for m in get(d, "milestone", Any[])]; by = m -> m.id)
    return GuidedProject(String(name), dir, Course.getstr(d, "package"), Course.getstr(d, "env"),
                         Course.getstr(d, "status", "planned"), Course.getstr(d, "title"),
                         Course.getstr(d, "summary"), strs(d, "kcs"), Course.getstr(d, "reading"),
                         ms, mutants, fixtures)
end

"""Every guided project, sorted by name."""
load_all(; root::String = GUIDED_DIR) =
    [load_guided(n; root) for n in sort!(readdir(root)) if isfile(joinpath(root, n, "project.toml"))]

milestone(p::GuidedProject, m::Int) = (i = findfirst(x -> x.id == m, p.milestones);
                                       i === nothing ? error("$(p.name) has no milestone $m") : p.milestones[i])
host_ok(p::GuidedProject) = p.env in HOST_ENVS

"""Learner-facing prose of a project, as (where, text) pairs (code stripped)."""
function prose(p::GuidedProject)
    out = Tuple{String,String}[("summary", p.summary), ("reading", Course.strip_code(p.reading))]
    for m in p.milestones
        w = "milestone $(m.id)"
        push!(out, (w, Course.strip_code(m.title * "\n" * m.goal * "\n" * join([a.doc for a in m.api], "\n"))))
        for b in m.behaviours
            push!(out, ("$w $(b.id)", Course.strip_code(join(vcat(b.spec, b.hints, b.test_hints), "\n"))))
        end
        for q in m.questions
            push!(out, ("$w question", Course.strip_code(join(vcat(q.prompt, q.explain, q.misconceptions,
                                                                  q.kind == "choice" ? q.choices : String[]), "\n"))))
        end
    end
    return out
end

"""Structural problems that need no Julia run (empty = none)."""
function validate(p::GuidedProject)
    out = String[]
    isempty(p.package) && push!(out, "$(p.name): no package name")
    isdir(Course.env_dir(p.env)) || push!(out, "$(p.name): env $(p.env) is not in course/envs")
    p.status in ("ready", "planned") || push!(out, "$(p.name): status must be ready or planned")
    isempty(p.milestones) && push!(out, "$(p.name): no milestones")
    ids = [m.id for m in p.milestones]
    ids == collect(0:length(ids)-1) || push!(out, "$(p.name): milestones must be numbered 0, 1, 2, ...")
    seen = Set{String}()
    for m in p.milestones, b in m.behaviours
        b.id in seen && push!(out, "$(p.name): behaviour id $(b.id) is used twice")
        push!(seen, b.id)
        length(b.hints) == 3 || push!(out, "$(p.name) $(b.id): needs exactly 3 hints")
        p.status == "ready" && length(b.test_hints) != 3 && push!(out, "$(p.name) $(b.id): needs exactly 3 test_hints")
        isempty(strip(b.spec)) && push!(out, "$(p.name) $(b.id): no spec")
        # No level gives the fix away: level 3 points at the line, not its content.
        for (lvl, h) in enumerate(b.hints), t in b.answer_tokens
            occursin(t, h) && push!(out, "$(p.name) $(b.id): level-$lvl hint contains the answer token `$t`")
        end
    end
    for m in p.milestones
        for c in m.must_cover
            any(b -> b.id == c, m.behaviours) || push!(out, "$(p.name) milestone $(m.id): must_cover $c is not a behaviour of it")
            p.status == "ready" && !any(x -> x.behaviour == c, p.mutants) &&
                push!(out, "$(p.name) milestone $(m.id): must_cover $c has no mutant")
        end
        0 < m.min_score <= 1 || push!(out, "$(p.name) milestone $(m.id): min_score must be in (0, 1]")
        if m.perf !== nothing
            s, w = m.perf, "$(p.name) milestone $(m.id) perf"
            any(a -> occursin(Regex("\\b\\Q" * s.entry * "\\E\\("), a.signature), m.api) ||
                push!(out, "$w: entry `$(s.entry)` is not in the milestone's API")
            isempty(s.cases) && push!(out, "$w: no cases")
            isempty(s.args) && push!(out, "$w: no args")
            length(s.sizes) in (1, 2) || push!(out, "$w: sizes needs one or two sizes")
            s.compare in ("isequal", "isapprox") || push!(out, "$w: compare must be isequal or isapprox")
            for x in s.fail_on
                x in PERF_FAIL_ON || push!(out, "$w: fail_on `$x` is not one of $(join(PERF_FAIL_ON, ", "))")
            end
        end
        for (i, q) in enumerate(m.questions)
            append!(out, ["$(p.name) milestone $(m.id) question $i: $x" for x in Course.question_problems(q)])
        end
    end
    # The course's length rule (Course.question_balance_problems), per project.
    cqs = [q for m in p.milestones for q in m.questions if q.kind == "choice"]
    if length(cqs) >= 4
        limit = floor(Int, Course.MAX_LONGEST_ANSWER_SHARE * length(cqs))
        extreme(q, ext) = (L = length.(q.choices); L[q.answer] == ext(L) && count(==(ext(L)), L) == 1)
        for (ext, word) in ((maximum, "longest"), (minimum, "shortest"))
            n = count(q -> extreme(q, ext), cqs)
            n > limit && push!(out, "$(p.name): in $n of $(length(cqs)) choice questions the answer is the " *
                                    "unique $word choice (at most $limit allowed)")
        end
    end
    mids = Set{String}()
    for x in p.mutants
        x.id in mids && push!(out, "$(p.name): mutant id $(x.id) is used twice")
        push!(mids, x.id)
        m = findfirst(y -> y.id == x.milestone, p.milestones)
        if m === nothing
            push!(out, "$(p.name) mutant $(x.id): no milestone $(x.milestone)")
        elseif !any(b -> b.id == x.behaviour, p.milestones[m].behaviours)
            push!(out, "$(p.name) mutant $(x.id): $(x.behaviour) is not a behaviour of milestone $(x.milestone)")
        end
    end
    for (where, txt) in prose(p)
        low = lowercase(txt)
        for w in Course.FILLER
            occursin(Regex("(?<![\\w-])\\Q" * w * "\\E(?![\\w-])"), low) &&
                push!(out, "$(p.name) $where: filler phrase \"$w\"")
        end
        occursin('—', txt) && push!(out, "$(p.name) $where: em dash (use a colon, comma or parentheses)")
    end
    if p.status == "ready"
        isfile(joinpath(p.dir, "reference", "src", p.package * ".jl")) ||
            push!(out, "$(p.name): no reference/src/$(p.package).jl")
        for m in p.milestones
            isfile(joinpath(p.dir, "acceptance", "m$(m.id).jl")) || push!(out, "$(p.name): no acceptance/m$(m.id).jl")
            isfile(joinpath(p.dir, "reference", "test", "m$(m.id).jl")) ||
                push!(out, "$(p.name): no reference/test/m$(m.id).jl (the exemplary student tests)")
        end
    end
    return out
end

# ---- mutants ------------------------------------------------------------------------

"""The reference's files with mutant `x` applied (errors unless `find` occurs exactly once)."""
function mutant_files(p::GuidedProject, x::Mutant, ref::Dict{String,String})
    key = "src/" * x.file
    haskey(ref, key) || error("mutant $(x.id): no reference file src/$(x.file)")
    src = ref[key]
    n = length(findall(x.find, src))
    n == 1 || error("mutant $(x.id): the `find` snippet occurs $n times in src/$(x.file) (must be once)")
    out = copy(ref)
    out[key] = replace(src, x.find => x.replace)
    return out
end

# ---- reading a project folder --------------------------------------------------------

"""
Files under `dir/sub` as relative path => text: `.jl` files (and, for
`data`, any file), at most `MAX_FILES` files and `MAX_BYTES` in total.
"""
function read_tree(dir::String, sub::String; all_files::Bool = false)
    out = Dict{String,String}()
    base = joinpath(dir, sub)
    isdir(base) || return out
    total = 0
    for (r, _, fs) in walkdir(base), f in sort(fs)
        (all_files || endswith(f, ".jl")) || continue
        path = joinpath(r, f)
        rel = replace(relpath(path, dir), '\\' => '/')
        total += filesize(path)
        (length(out) >= MAX_FILES || total > MAX_BYTES) &&
            error("$dir/$sub holds more than $MAX_FILES files or $(MAX_BYTES ÷ 1_000_000) MB; the check sends at most that")
        out[rel] = replace(read(path, String), "\r\n" => "\n")
    end
    return out
end

"""What is missing from a student's folder for milestone 0's layout (empty = nothing)."""
function layout_problems(p::GuidedProject, dir::String)
    out = String[]
    isfile(joinpath(dir, "src", p.package * ".jl")) ||
        push!(out, "There is no src/$(p.package).jl. Milestone 0 creates it: `tutor guided show $(p.name) 0`.")
    isfile(joinpath(dir, "test", "runtests.jl")) ||
        push!(out, "There is no test/runtests.jl. Milestone 0 creates it: `tutor guided show $(p.name) 0`.")
    return out
end

# ---- the job ---------------------------------------------------------------------------

prefix(files::Dict{String,String}, pre::String) = Dict(pre * "/" * k => v for (k, v) in files)

"""The reference package's files (src/ and test/, relative to reference/)."""
reference_files(p::GuidedProject) = merge(read_tree(joinpath(p.dir, "reference"), "src"),
                                          read_tree(joinpath(p.dir, "reference"), "test"))

"""Acceptance tests and the data they read, under `acceptance/`."""
acceptance_files(p::GuidedProject) = merge(read_tree(p.dir, "acceptance"),
                                           prefix(read_tree(joinpath(p.dir, "acceptance"), "data"; all_files = true), "acceptance"))

"""Files the student gets in `data/` from `tutor guided start`."""
data_files(p::GuidedProject) = read_tree(p.dir, "data"; all_files = true)

"""
The driver job for checking the student's folder at milestone `m`. Runs, in
order: acceptance tests of milestones 0..m on the student's code; the
student's tests on their code, on the reference, then on each mutant of
milestones 1..m.
"""
function check_job(p::GuidedProject, student::Dict{String,String}, m::Int)
    # Only the reference's src/: its exemplary tests stay out of a student's
    # check (a student's `include("m1.jl")` must not find them).
    ref = Dict(k => v for (k, v) in reference_files(p) if startswith(k, "src/"))
    files = merge(prefix(student, "student"), acceptance_files(p))
    # The reference and the mutants get neutral names in a seeded shuffle, so
    # a test cannot tell from `@__DIR__` which implementation it runs on.
    muts = [x for x in p.mutants if 1 <= x.milestone <= m]
    keys_ = vcat(["reference"], [x.id for x in muts])
    order = sortperm([hash(string(SEED, ':', p.name, ':', k)) for k in keys_])
    name = Dict(keys_[j] => "impl_$i" for (i, j) in enumerate(order))
    # Every implementation directory gets the student's test/ and data/ (the
    # tests read data through @__DIR__) next to its own src/.
    own = Dict(k => v for (k, v) in student if startswith(k, "test/") || startswith(k, "data/"))
    runs = Any[]
    for k in 0:m
        push!(runs, Dict("label" => "acceptance m$k", "impl" => "student", "tests" => "acceptance/m$k.jl"))
    end
    push!(runs, Dict("label" => "own tests on own code", "impl" => "student", "tests" => "student/test/runtests.jl"))
    d = name["reference"]
    merge!(files, prefix(ref, d), prefix(own, d))
    impls = Any[Dict("label" => "own tests on reference", "impl" => d, "tests" => d * "/test/runtests.jl")]
    for x in muts
        d = name[x.id]
        src = Dict(k => v for (k, v) in mutant_files(p, x, ref) if startswith(k, "src/"))
        merge!(files, prefix(src, d), prefix(own, d))
        push!(impls, Dict("label" => "own tests on mutant $(x.id)", "impl" => d, "tests" => d * "/test/runtests.jl",
                          "mutant" => x.id))
    end
    # Run them in the shuffled order too: the reference is not always first.
    append!(runs, sort!(impls; by = r -> parse(Int, r["impl"][6:end])))
    return Dict("package" => p.package, "seed" => SEED, "files" => files, "runs" => runs)
end

"""The driver program with `job` embedded (base64 TOML: no quoting issues)."""
function driver_source(job)
    io = IOBuffer()
    TOML.print(io, job; sorted = true)
    return "GUIDED_JOB = \"" * base64encode(take!(io)) * "\"\n" * read(DRIVER, String)
end

run_timeout(p::GuidedProject) = host_ok(p) ? 600 : 1200

"""Run a job in the sandbox. Returns (raw result or nothing, timed_out, log)."""
function run_job(p::GuidedProject, job; timeout::Real = run_timeout(p))
    dir = mktempdir()
    path = joinpath(dir, "main.jl")
    write(path, driver_source(job))
    rc, to, log = Practice.child(["run", path, "file"], dir; env = p.env, timeout)
    out = joinpath(dir, "result.toml")
    raw = isfile(out) ? TOML.parsefile(out) : nothing
    try rm(dir; recursive = true, force = true) catch end
    return raw, to, Practice.clip(log, 20_000)
end

"""The last stage marker the driver printed (where a timeout happened)."""
function last_stage(log::AbstractString)
    ms = collect(eachmatch(Regex("\\Q" * STAGE * "\\E ([^\\n]*)"), log))
    return isempty(ms) ? "" : String(strip(ms[end].captures[1]))
end

# ---- assessing a check ---------------------------------------------------------------------

item(level, title, detail = "") = Practice.item(level, title, detail)

run_ok(r) = !haskey(r, "load_error") && !get(r, "tests_missing", false) && isempty(get(r, "toplevel_error", "")) &&
            all(s -> s["failed"] == 0 && s["errored"] == 0, get(r, "testsets", Any[]))
run_by(raw, label) = (i = findfirst(r -> r["label"] == label, raw["runs"]); i === nothing ? nothing : raw["runs"][i])

"""Behaviour ids of milestones 0..m with their milestone."""
behaviours_upto(p, m) = [(x, b) for x in p.milestones if x.id <= m for b in x.behaviours]

hint_level(levels, key) = clamp(get(levels, key, 1), 1, 3)

"""
    assess(p, m, raw; timed_out, log, findings, levels) -> Dict

Pure function from the driver's result to verdicts and feedback for milestone
`m`. `levels` maps "acc:<behaviour>" / "test:<behaviour>" to the hint level to
show (1-3). Keys: `status` ("passed" or "not-yet"), `verdicts`, `feedback`
(items with level pass/warn/fail/info, as in `Practice.assess`), `failing`
(behaviour ids whose acceptance tests fail), `surviving` (mutant ids),
`score` (killed / total, or nothing without mutants).
"""
function assess(p::GuidedProject, m::Int, raw; timed_out::Bool = false, log::AbstractString = "",
                findings = Checker.Finding[], levels = Dict{String,Int}())
    ms = milestone(p, m)
    out = Dict{String,Any}("project" => p.name, "milestone" => m, "feedback" => Any[], "verdicts" => String[],
                           "failing" => String[], "surviving" => String[], "score" => nothing, "shown" => String[])
    fb = out["feedback"]; v = out["verdicts"]
    blocking = filter(f -> f.severity >= Checker.WARN, findings)
    if raw === nothing || !get(raw, "complete", false)
        stage = last_stage(log)
        if timed_out
            push!(fb, item("fail", "Timed out" * (isempty(stage) ? "" : " during: $stage"),
                           "An infinite loop, or a test that does far more work than needed. Nothing after that point ran."))
            push!(v, "timeout")
        else
            push!(fb, item("fail", "The check crashed" * (isempty(stage) ? "" : " during: $stage"), strip(log)))
            push!(v, "crash")
        end
        out["status"] = "not-yet"
        return out
    end
    beh = Dict(b.id => b for (_, b) in behaviours_upto(p, m))

    # 1. The student's code against the hidden acceptance tests.
    own = run_by(raw, "own tests on own code")
    if haskey(own, "load_error")
        push!(fb, item("fail", "Your package does not load", own["load_error"]))
        push!(v, "load-error")
    else
        failing = String[]
        detail = Dict{String,String}()
        unrun = false   # an acceptance file that stopped outside its test sets
        for k in 0:m
            r = run_by(raw, "acceptance m$k")
            if r === nothing || haskey(r, "load_error") || get(r, "tests_missing", false) || !haskey(r, "total")
                push!(fb, item("fail", "The acceptance tests of milestone $k did not run", get(r === nothing ? Dict() : r, "load_error", "")))
                unrun = true
                continue
            end
            for s in get(r, "testsets", Any[])
                (s["failed"] > 0 || s["errored"] > 0) || continue
                id = String(last(split(s["name"], '/')))
                haskey(beh, id) || continue
                id in failing || push!(failing, id)
                if s["errored"] > 0 && !isempty(s["errors"]) && !haskey(detail, id)
                    detail[id] = "It throws: " * first(s["errors"])
                end
            end
            if !isempty(get(r, "toplevel_error", ""))
                # Outside every test set: usually a name the milestone's API
                # requires is missing, or a call at top level throws.
                push!(fb, item("fail", "The acceptance tests of milestone $k stopped early", r["toplevel_error"]))
                unrun = true
            end
        end
        out["failing"] = failing
        unrun && push!(v, "acceptance-fail")
        if isempty(failing) && !unrun
            n = sum(k -> (r = run_by(raw, "acceptance m$k"); r === nothing ? 0 : r["total"]), 0:m)
            push!(fb, item("pass", "Behaviour: every acceptance check passes",
                           "$n checks over milestones 0 to $m, on your code."))
        elseif !isempty(failing)
            push!(v, "acceptance-fail")
            # One thing at a time: the first failing behaviour (milestone and
            # spec order) gets the spec and a hint; later ones often follow
            # from it (a wrong conversion also breaks the duplicate check).
            id = failing[1]
            b = beh[id]
            lvl = hint_level(levels, "acc:" * id)
            push!(out["shown"], "acc:" * id)
            txt = b.spec * (haskey(detail, id) ? "\n" * detail[id] : "") * "\nHint $lvl: " * b.hints[lvl]
            push!(fb, item("fail", "Behaviour `$id` is not right yet", txt))
            length(failing) > 1 &&
                push!(fb, item("info", "Also not right yet: " * join(["`$x`" for x in failing[2:end]], ", "),
                               "Fix `$id` first and check again: the others may follow from it."))
        end
    end

    # 2. The student's tests against the reference: they must agree with the spec.
    refrun = run_by(raw, "own tests on reference")
    if get(refrun, "tests_missing", false)
        push!(fb, item("fail", "No test/runtests.jl", "Milestone 0 sets it up."))
        push!(v, "no-tests")
    elseif !isempty(get(refrun, "toplevel_error", ""))
        te = refrun["toplevel_error"]
        note = occursin(r"^(UndefVarError|MethodError)", te) ?
            "\nTests may use only the API that `tutor guided show` lists: they also run on other correct implementations." : ""
        push!(fb, item("fail", "Your test file stops with an error outside any @testset (on a correct implementation)", te * note))
        push!(v, "tests-fail-reference")
    elseif refrun["total"] == 0
        push!(fb, item("fail", "Your test suite runs no @test", "Every behaviour in the milestone needs at least one check."))
        push!(v, "no-tests")
    elseif !run_ok(refrun)
        bad = [s for s in refrun["testsets"] if s["failed"] > 0 || s["errored"] > 0]
        msgs = join(vcat([s["messages"] for s in bad]...)[1:min(end, 3)], "\n\n")
        errs = vcat([s["errors"] for s in bad]...)
        # A name the reference lacks: the test reaches past the milestone API.
        offapi = any(e -> occursin(r"^(UndefVarError|MethodError)", e), errs)
        why = offapi ?
            "These tests call something the milestone API does not define (a helper of your own, or another " *
            "signature). Tests may use only the API that `tutor guided show` lists, since they also run on " *
            "other correct implementations; test helpers through the API functions that use them:\n\n" :
            "These tests disagree with the milestone spec (a correct implementation fails them), " *
            "so they would reject right code:\n\n"
        push!(fb, item("fail", "Some of your tests fail on a correct implementation", why * msgs))
        push!(v, "tests-fail-reference")
    else
        push!(fb, item("pass", "Your tests pass on a correct implementation", "$(refrun["total"]) checks."))
    end

    # 3. The student's tests against the mutants: do they notice broken behaviour?
    mruns = [r for r in raw["runs"] if startswith(r["label"], "own tests on mutant ")]
    if !isempty(mruns) && "tests-fail-reference" ∉ v && "no-tests" ∉ v
        mut = Dict(x.id => x for x in p.mutants)
        mid(r) = String(replace(r["label"], "own tests on mutant " => ""))
        surv = [mid(r) for r in mruns if run_ok(r)]
        out["surviving"] = surv
        # Each milestone is scored on its own mutants: tests that kill every
        # earlier fault must not carry a milestone whose new behaviour they
        # miss. Earlier milestones stay a regression gate at their own bar.
        weak = false
        uncovered = String[]
        for k in 1:m
            mk = filter(r -> mut[mid(r)].milestone == k, mruns)
            isempty(mk) && continue
            kms = milestone(p, k)
            killed = count(r -> !run_ok(r), mk)
            sk = killed / length(mk)
            k == m && (out["score"] = sk)
            for c in kms.must_cover
                any(r -> mut[mid(r)].behaviour == c && !run_ok(r), mk) || push!(uncovered, c)
            end
            line = "$killed of $(length(mk)) seeded faults of milestone $k make your tests fail."
            need = round(Int, 100kms.min_score)
            if sk >= kms.min_score
                k == m && push!(fb, item("pass", "Test strength: $(round(Int, 100sk))% of this milestone's seeded faults caught", line))
            else
                weak = true
                push!(fb, item("fail", k == m ?
                    "Test strength: $(round(Int, 100sk))% of this milestone's seeded faults caught (it needs $need%)" :
                    "Test strength on milestone $k dropped to $(round(Int, 100sk))% (it needs $need%)", line))
            end
        end
        if !isempty(uncovered)
            weak = true
            push!(fb, item("fail", "Not covered: " * join(["`$c`" for c in uncovered], ", "),
                           "The milestone requires your tests to notice a fault in each of these; none of their seeded faults makes a test fail."))
        end
        weak && push!(v, "weak-tests")
        # Advice: uncovered required behaviours first, then the rest in spec order.
        missed = unique(vcat(uncovered, [mut[id].behaviour for id in surv]))
        for bid in missed[1:min(end, MAX_TEST_ADVICE)]
            b = beh[bid]
            lvl = hint_level(levels, "test:" * b.id)
            push!(out["shown"], "test:" * b.id)
            push!(fb, item(weak ? "warn" : "info", "Your tests do not notice when `$(b.id)` breaks",
                           b.spec * "\nWhat to test ($lvl): " * b.test_hints[lvl]))
        end
        length(missed) > MAX_TEST_ADVICE &&
            push!(fb, item("info", "Your tests also miss faults in: " * join(["`$x`" for x in missed[MAX_TEST_ADVICE+1:end]], ", "), ""))
    end
    # Informative: the student's tests on their own code.
    if !haskey(own, "load_error") && !get(own, "tests_missing", false) && get(own, "total", 0) > 0 && !run_ok(own)
        push!(fb, item("info", "Your own tests fail on your code", "Fix the code or the test: the acceptance results above say which one is off."))
    end

    # 4. The static checker.
    if isempty(blocking)
        push!(fb, item("pass", "Checker: no warnings", isempty(findings) ? "" : "$(length(findings)) advice note(s) below."))
    else
        push!(v, "checker-warn")
        push!(fb, item("fail", "Checker: $(length(blocking)) warning(s)", "See the findings below (`--hints=1` for hints)."))
    end
    out["status"] = isempty(v) ? "passed" : "not-yet"
    isempty(v) && push!(v, "passed")
    return out
end

"""Plain-text rendering of a check for the terminal."""
function format_check(r, findings = Checker.Finding[]; hints::Int = 0)
    io = IOBuffer()
    mark = Dict("pass" => "✓", "warn" => "!", "fail" => "✗", "info" => "·")
    println(io, "Milestone ", r["milestone"], ": ", r["status"] == "passed" ? "passed" : "not yet")
    for f in r["feedback"]
        println(io, mark[f["level"]], " ", f["title"])
        isempty(f["detail"]) || println(io, "    ", replace(f["detail"], "\n" => "\n    "))
    end
    isempty(findings) || print(io, Checker.format_findings(findings; hints))
    return String(take!(io))
end

# ---- state: passed milestones and hint fading ------------------------------------------------

const DEFAULT_STATE = joinpath(".tutor", "guided.toml")

load_state(path) = isfile(path) ? TOML.parsefile(path) : Dict{String,Any}()
save_state(path, s) = (mkpath(dirname(abspath(path))); open(io -> TOML.print(io, s; sorted = true), path, "w"))

statekey(p::GuidedProject, dir) = p.name * ":" * replace(abspath(dir), '\\' => '/')

"""Hint levels for a check: consecutive failures so far + 1, from the state."""
function levels_from(state, key)
    s = get(get(state, "projects", Dict()), key, Dict())
    return Dict{String,Int}(k => v + 1 for (k, v) in get(s, "streaks", Dict()))
end

"""
Record a check: passed milestones, and per behaviour the number of checks in
a row whose feedback showed a hint for it (the next one shows the next level).
A behaviour that fails but was not shown keeps its level; one that passes
starts over. A check that did not run (timeout, crash) changes no streak.
"""
function record!(state, key, r, p::GuidedProject)
    projs = get!(state, "projects", Dict{String,Any}())
    s = get!(projs, key, Dict{String,Any}("passed" => Int[], "streaks" => Dict{String,Any}()))
    streaks = get!(s, "streaks", Dict{String,Any}())
    m = r["milestone"]
    ran = !any(in(("timeout", "crash", "no-layout", "load-error")), r["verdicts"])
    # Mutants are not run against tests that fail on the reference (or are
    # missing): that check says nothing about test strength, so it keeps the
    # test-hint streaks as they are.
    tested = ran && !any(in(("tests-fail-reference", "no-tests")), r["verdicts"])
    mutb = Dict(x.id => x.behaviour for x in p.mutants)
    bad = Set(vcat(["acc:" * b for b in r["failing"]], ["test:" * mutb[x] for x in r["surviving"]]))
    shown = Set(get(r, "shown", String[]))
    for (_, b) in behaviours_upto(p, m), k in ("acc:" * b.id, "test:" * b.id)
        ran || break
        startswith(k, "test:") && !tested && continue
        if k in shown
            streaks[k] = get(streaks, k, 0) + 1
        elseif !(k in bad)
            delete!(streaks, k)
        end
    end
    r["status"] == "passed" && !(m in s["passed"]) && (s["passed"] = sort!(push!(Int.(s["passed"]), m)))
    return state
end

"""The first milestone not yet passed for this folder (the last one if all are)."""
function next_milestone(p::GuidedProject, state, key)
    passed = Set(get(get(get(state, "projects", Dict()), key, Dict()), "passed", Int[]))
    for m in p.milestones
        m.id in passed || return m.id
    end
    return p.milestones[end].id
end

# ---- the check -------------------------------------------------------------------------------

"""Student files to send: src/ and test/ (.jl), data/ (any)."""
student_files(dir::String) = merge(read_tree(dir, "src"), read_tree(dir, "test"), read_tree(dir, "data"; all_files = true))

"""Checker findings on the student's src/ and test/ (text only; nothing is run)."""
function student_findings(dir::String)
    paths = filter(isdir, [joinpath(dir, "src"), joinpath(dir, "test")])
    isempty(paths) && return Checker.Finding[]
    return Checker.check_paths(paths; relative_to = dir)
end

"""
Check the student's folder `dir` at milestone `m`. Returns (result, findings).
`levels` overrides the hint level of every behaviour when `hints > 0`.
"""
function check(p::GuidedProject, dir::String, m::Int; levels = Dict{String,Int}(), hints::Int = 0)
    p.status == "ready" || error("$(p.name) is planned (spec only); its reference and tests are not built yet")
    lp = layout_problems(p, dir)
    if !isempty(lp)
        r = Dict{String,Any}("project" => p.name, "milestone" => m, "status" => "not-yet", "verdicts" => ["no-layout"],
                             "failing" => String[], "surviving" => String[], "score" => nothing,
                             "feedback" => Any[item("fail", "The package layout is not there yet", join(lp, "\n"))])
        return r, Checker.Finding[]
    end
    findings = student_findings(dir)
    raw, to, log = run_job(p, check_job(p, student_files(dir), m))
    if hints > 0
        levels = Dict{String,Int}()
        for (_, b) in behaviours_upto(p, m)
            levels["acc:" * b.id] = hints; levels["test:" * b.id] = hints
        end
    end
    r = assess(p, m, raw; timed_out = to, log, findings, levels)
    spec = milestone(p, m).perf
    if spec !== nothing
        if any(in(("acceptance-fail", "load-error", "timeout", "crash")), r["verdicts"])
            push!(r["feedback"], item("info", "Performance is graded once the acceptance tests pass"))
        else
            merge_perf!(r, spec, grade_perf(p, m, student_files(dir)))
        end
    end
    return r, findings
end

# ---- performance ([milestone.perf]) -----------------------------------------------------------

"""
The package as one source text: lines that are only `include("x.jl")` are
replaced by that file from `files` (relative to the including file). Host side,
text only: nothing is run.
"""
function inline_includes(files::Dict{String,String}, path::String; depth::Int = 0)
    out = IOBuffer()
    for line in split(files[path], '\n')
        mm = match(r"^\s*include\(\"([^\"$]+)\"\)\s*(#.*)?$", line)
        key = mm === nothing ? "" : replace(normpath(joinpath(dirname(path), mm[1])), '\\' => '/')
        if depth < 8 && haskey(files, key)
            println(out, inline_includes(files, key; depth = depth + 1))
        else
            println(out, line)
        end
    end
    return String(take!(out))
end

"""Source handed to `Practice.grade`: the package module, then its entry brought into scope."""
function perf_source(files::Dict{String,String}, pkg::String, entry::String)
    path = "src/$pkg.jl"
    haskey(files, path) || return "error(\"no src/$pkg.jl\")\n"
    return inline_includes(files, path) * "\nusing .$pkg: $entry\n"
end

function perf_problem(p::GuidedProject, m::Int)
    s = milestone(p, m).perf
    ref = perf_source(reference_files(p), p.package, s.entry)
    return Course.load_problem(Dict{String,Any}(
        "id" => "$(p.name)-m$m", "title" => "$(p.package).$(s.entry)", "difficulty" => "guided", "prompt" => "",
        "entry" => s.entry, "starter" => "", "reference" => ref, "cases" => s.cases, "compare" => s.compare,
        "rtol" => s.rtol, "check_type" => true,
        "perf" => Dict{String,Any}("args" => s.args, "sizes" => s.sizes, "mutates" => s.mutates)))
end

"""Grade the student's entry function for milestone `m` (in the sandbox, like a practice problem)."""
grade_perf(p::GuidedProject, m::Int, student::Dict{String,String}) =
    Practice.grade(perf_problem(p, m), perf_source(student, p.package, milestone(p, m).perf.entry);
                   env = p.env, timeout = run_timeout(p))

"""
Fold a `Practice.grade` result into a check result (pure). A required perf
section blocks the milestone when grading did not pass or gave one of its
`fail_on` verdicts; an optional one only reports.
"""
function merge_perf!(r, spec::PerfSpec, pr)
    r["performance"] = get(pr, "performance", nothing)
    pv = get(pr, "verdicts", String[])
    bad = get(pr, "status", "") != "passed" ? ["incorrect"] : filter(in(spec.fail_on), pv)
    for f in get(pr, "feedback", Any[])
        lvl = f["level"] == "fail" && !spec.required ? "warn" : f["level"]
        push!(r["feedback"], item(lvl, "Performance (`$(spec.entry)`): " * f["title"], get(f, "detail", "")))
    end
    if spec.required && !isempty(bad)
        filter!(!=("passed"), r["verdicts"])
        push!(r["verdicts"], "perf-fail")
        r["status"] = "not-yet"
    end
    return r
end

# ---- start, show, deps --------------------------------------------------------------------------

function guide_text(p::GuidedProject)
    io = IOBuffer()
    println(io, "# ", p.title, "\n\n", strip(p.summary), "\n")
    isempty(strip(p.reading)) || println(io, strip(p.reading), "\n")
    println(io, "Milestones:")
    for m in p.milestones
        println(io, "  ", m.id, ". ", m.title)
    end
    println(io, "\nRead a milestone with `tutor guided show $(p.name) <m>`, check it with ",
            "`tutor guided check <this folder> <m>`.")
    return String(take!(io))
end

"""The files `tutor guided start` creates: data/ and GUIDE.md. No code."""
start_files(p::GuidedProject) = merge(data_files(p), Dict("GUIDE.md" => guide_text(p)))

"""The milestone spec as text."""
function show_milestone(p::GuidedProject, m::Int)
    ms = milestone(p, m)
    io = IOBuffer()
    println(io, p.title, ": milestone ", ms.id, " of ", p.milestones[end].id, ", ", ms.title, "\n")
    println(io, strip(ms.goal), "\n")
    if !isempty(ms.api)
        println(io, "API to write:")
        for a in ms.api
            println(io, "  ", a.signature)
            isempty(strip(a.doc)) || println(io, "      ", replace(strip(a.doc), "\n" => "\n      "))
        end
        println(io)
    end
    if !isempty(ms.behaviours)
        println(io, "Behaviour (each id is what the check reports):")
        for b in ms.behaviours
            println(io, "  [", b.id, "] ", replace(strip(b.spec), "\n" => "\n      "))
        end
        println(io)
    end
    if !isempty(ms.must_cover)
        println(io, "Your tests must cover: ", join(ms.must_cover, ", "), ".")
        println(io, "The check runs them against seeded faults in a correct implementation; ",
                "this milestone needs $(round(Int, 100ms.min_score))% of its own faults caught, ",
                "and at least one fault caught in each of those behaviours.\n")
    end
    ms.id > 0 && println(io, "Your tests may use only the API above (and earlier milestones'): ",
                         "they also run on other correct implementations, which have no helpers of yours.\n")
    if ms.perf !== nothing
        println(io, "Performance: `$(ms.perf.entry)` is also graded against the reference (speed, allocations, ",
                "growth with input size, type stability), once the acceptance tests pass",
                ms.perf.required ? "; this blocks the milestone" : " (reported only)", ".\n")
    end
    isempty(ms.questions) || println(io, "Concept questions: tutor guided quiz $(p.name) $(ms.id)\n")
    return String(take!(io))
end

"""
`Project.toml` text with `[deps]` set to the project's environment packages
(UUIDs from course/envs/<env>/Project.toml); other sections are kept.
"""
function with_deps(project_toml::AbstractString, env::AbstractString)
    d = TOML.parse(project_toml)
    envd = TOML.parsefile(joinpath(Course.env_dir(env), "Project.toml"))
    deps = get!(d, "deps", Dict{String,Any}())
    merge!(deps, get(envd, "deps", Dict{String,Any}()))
    # Test is a test-only dependency, as `Pkg.generate` + `Pkg.add` would set it up.
    extras = get!(d, "extras", Dict{String,Any}())
    extras["Test"] = "8dfed614-e22c-5e08-85e1-65c5234f0b40"
    get!(d, "targets", Dict{String,Any}("test" => ["Test"]))
    io = IOBuffer()
    TOML.print(io, d; sorted = true)
    return String(take!(io))
end

# ---- concept questions ---------------------------------------------------------------------------

"""Ask milestone `m`'s questions on `io`, reading answers from `input`; returns (right first time, total)."""
function quiz(p::GuidedProject, m::Int; input::IO = stdin, io::IO = stdout)
    qs = milestone(p, m).questions
    first_try = 0
    for (i, q) in enumerate(qs)
        println(io, "\nQuestion $i of $(length(qs)): ", q.prompt)
        isempty(q.code) || println(io, "\n", q.code)
        for (j, c) in enumerate(q.choices)
            println(io, "  ", j, ") ", c)
        end
        tries = 0
        while true
            print(io, "> ")
            line = readline(input)
            k = tryparse(Int, strip(line))
            if eof(input) && k === nothing
                return first_try, length(qs)
            end
            (k === nothing || !(1 <= k <= length(q.choices))) && (println(io, "Pick 1 to $(length(q.choices))."); continue)
            tries += 1
            if k == q.answer
                tries == 1 && (first_try += 1)
                println(io, "Right. ", q.explain)
                break
            end
            println(io, "Not quite: ", q.misconceptions[k])
        end
    end
    return first_try, length(qs)
end

# ---- website data (site/data/guided.json) ------------------------------------------------------
#
# The spec only: goals, API, behaviours with their hint ladders, concept
# questions, and counts. Never the reference, the acceptance tests or what a
# mutant changes (the site must not hand out what the check keeps hidden).

function site_data(; root::String = GUIDED_DIR)
    ps = load_all(; root)
    projects = Any[]
    for p in ps
        ms = Any[]
        for m in p.milestones
            push!(ms, Dict("id" => m.id, "title" => m.title, "goal" => strip(m.goal),
                           "api" => Any[Dict("signature" => a.signature, "doc" => strip(a.doc)) for a in m.api],
                           # Level 1 only: levels 2 and 3 fade in from `tutor guided check`.
                           "behaviours" => Any[Dict("id" => b.id, "kc" => b.kc, "spec" => strip(b.spec), "hints" => b.hints[1:min(end, 1)],
                                                    "test_hints" => b.test_hints[1:min(end, 1)]) for b in m.behaviours],
                           "must_cover" => m.must_cover, "min_score" => m.min_score,
                           "mutants" => count(x -> x.milestone == m.id, p.mutants),
                           "perf_entry" => m.perf === nothing ? "" : m.perf.entry,
                           "questions" => Any[Dict("kind" => q.kind, "prompt" => strip(q.prompt), "code" => rstrip(q.code),
                                                   "choices" => q.choices, "answer" => q.answer, "explain" => strip(q.explain),
                                                   "misconceptions" => q.misconceptions) for q in m.questions]))
        end
        push!(projects, Dict("name" => p.name, "package" => p.package, "env" => p.env, "status" => p.status,
                             "title" => p.title, "summary" => p.summary, "kcs" => p.kcs, "reading" => strip(p.reading),
                             "host_ok" => host_ok(p), "packages" => Practice.env_deps(p.env), "milestones" => ms))
    end
    return Dict("julia" => string(VERSION), "generated_by" => "tutor site-data (do not edit; regenerate)",
                "projects" => projects)
end

# ---- authoring self-test -----------------------------------------------------------------------

"""
The exemplary student suite for milestone `m`: reference/test/m0.jl .. m<m>.jl
included from a runtests.jl, as a student would split it.
"""
function exemplar_files(p::GuidedProject, m::Int)
    ref = reference_files(p)
    out = Dict{String,String}(k => v for (k, v) in ref if startswith(k, "test/") && k != "test/runtests.jl")
    out["test/runtests.jl"] = "using $(p.package), Test\n\n" *
                              join(["include(\"m$k.jl\")" for k in 0:m if haskey(out, "test/m$k.jl")], "\n") * "\n"
    return out
end

"""
Self-test of a ready project (runs Julia in the sandbox). Returns a list of
problems (empty = verified). Checks: structure (`validate`); the reference
passes every acceptance test and the exemplary tests and has no checker
warnings; every mutant applies, fails an acceptance test set of its own
behaviour and is killed by the exemplary tests; every fixture gets its
declared verdicts; output questions match the measured output.
"""
function verify_project(p::GuidedProject; log::IO = stdout)
    problems = validate(p)
    p.status == "ready" || return problems
    isempty(problems) || return problems
    refdir = joinpath(p.dir, "reference")
    fs = filter(f -> f.severity >= Checker.WARN, Checker.check_paths([joinpath(refdir, "src")]; relative_to = refdir))
    append!(problems, ["$(p.name): reference has a checker warning: $(f.file):$(f.line) $(f.rule) $(f.message)" for f in fs])
    last_m = p.milestones[end].id
    ref = reference_files(p)
    student = merge(ref, exemplar_files(p, last_m), data_files(p))
    # One job: acceptance on the reference and on every mutant; the exemplary suite of
    # each mutant's milestone on that mutant.
    files = merge(prefix(student, "reference"), acceptance_files(p))
    runs = Any[]
    for k in 0:last_m
        push!(runs, Dict("label" => "acceptance m$k on reference", "impl" => "reference", "tests" => "acceptance/m$k.jl"))
    end
    push!(runs, Dict("label" => "exemplar on reference", "impl" => "reference", "tests" => "reference/test/runtests.jl"))
    for x in p.mutants
        d = "mutant_" * x.id
        mf = try
            mutant_files(p, x, ref)
        catch e
            push!(problems, "$(p.name): " * sprint(showerror, e)); continue
        end
        for (k, v) in mf
            startswith(k, "src/") && (files[d * "/" * k] = v)
        end
        for (k, v) in merge(exemplar_files(p, x.milestone), data_files(p))
            files[d * "/" * k] = v
        end
        push!(runs, Dict("label" => "acceptance m$(x.milestone) on $d", "impl" => d, "tests" => "acceptance/m$(x.milestone).jl"))
        push!(runs, Dict("label" => "exemplar on $d", "impl" => d, "tests" => d * "/test/runtests.jl"))
    end
    raw, to, out = run_job(p, Dict("package" => p.package, "seed" => SEED, "files" => files, "runs" => runs))
    if raw === nothing || !get(raw, "complete", false)
        push!(problems, "$(p.name): the verify job did not finish" * (to ? " (timed out at $(last_stage(out)))" : "") * ":\n" * out)
        return problems
    end
    for r in raw["runs"]
        lbl = r["label"]
        ok = run_ok(r)
        println(log, "  ", rpad(lbl, 56), ok ? "pass" : "fail")
        if endswith(lbl, "on reference")
            ok || push!(problems, "$(p.name): $lbl fails:\n" * join(vcat(get(r, "load_error", ""), get(r, "toplevel_error", ""),
                                                                         [m for s in get(r, "testsets", Any[]) for m in s["messages"]]...), "\n"))
        elseif startswith(lbl, "exemplar on mutant_")
            ok && push!(problems, "$(p.name): the exemplary tests do not kill $(replace(lbl, "exemplar on " => ""))")
        elseif startswith(lbl, "acceptance")
            id = String(last(split(lbl, "mutant_")))
            x = p.mutants[findfirst(y -> y.id == id, p.mutants)]
            # A mutant that does not load would be "killed" by every suite: it must load.
            if haskey(r, "load_error")
                push!(problems, "$(p.name): mutant $id does not load: $(r["load_error"])")
                continue
            end
            hit = any(s -> last(split(s["name"], '/')) == x.behaviour && (s["failed"] > 0 || s["errored"] > 0), get(r, "testsets", Any[]))
            hit || push!(problems, "$(p.name): mutant $id does not fail the acceptance test set `$(x.behaviour)`")
        end
    end
    # Output questions: the key is the measured output.
    for m in p.milestones, (i, q) in enumerate(m.questions)
        q.kind == "output" || continue
        rr = Practice.run_code(q.code; env = p.env, timeout = run_timeout(p))
        got = rstrip(rr.output)
        rstrip(q.choices[q.answer]) == got ||
            push!(problems, "$(p.name) milestone $(m.id) question $i: the answer is not the code's output:\n$got")
    end
    # Perf sections: the reference graded as a submission passes and gets none of its fail_on verdicts.
    for m in p.milestones
        m.perf === nothing && continue
        pr = grade_perf(p, m.id, ref)
        bad = filter(in(m.perf.fail_on), pr["verdicts"])
        println(log, "  ", rpad("perf m$(m.id) on reference", 56), join(pr["verdicts"], ","))
        (pr["status"] == "passed" && isempty(bad)) ||
            push!(problems, "$(p.name) milestone $(m.id): the reference fails its own perf grading: " *
                            "$(pr["status"]) [$(join(pr["verdicts"], ", "))]\n" * get(pr, "log", ""))
    end
    # Fixtures: student-like folders with their expected verdicts.
    for f in p.fixtures
        fdir = joinpath(p.dir, "fixtures", f.name)
        r, _ = check(p, fdir, f.milestone)
        println(log, "  fixture ", rpad(f.name, 47), join(r["verdicts"], ","))
        for e in f.expect
            e in r["verdicts"] || push!(problems, "$(p.name) fixture $(f.name): expected verdict '$e', got [$(join(r["verdicts"], ", "))]")
        end
        "passed" in f.expect || !("passed" in r["verdicts"]) ||
            push!(problems, "$(p.name) fixture $(f.name): passed but should not")
    end
    return problems
end

end # module Guided
