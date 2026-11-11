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

struct Example
    code::String
    check::Bool          # false: output varies run to run (timings, threads); recorded, not compared
    caption::String      # introduces the example; shown above the code
    mode::String         # "repl" (default: REPL soft scope, like the sandbox) or "file" (include semantics)
    notice::String       # what to look at in the result; shown under the output (and figures)
end
Example(code, check, caption, mode) = Example(code, check, caption, mode, "")

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

struct Section
    title::String
    body::String
    examples::Vector{Example}
    questions::Vector{Question}
end

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
end

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
end

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
    return Problem(d["id"], d["title"], d["difficulty"], String.(get(d, "kcs", String[])), d["prompt"],
                   d["entry"], d["starter"], d["reference"], String.(get(d, "cases", String[])),
                   getstr(d, "gen"), getstr(d, "compare", "isequal"), getstr(d, "checker"), Float64(get(d, "rtol", 1e-8)),
                   get(d, "check_type", true), get(d, "compare_args", false),
                   String.(get(d, "hints", String[])), perf, variants,
                   Int(get(d, "threads", 1)), Int(get(d, "repeats", 1)), String.(get(d, "packages", String[])))
end

# Git on Windows may check files out with CRLF; example keys hash the code, so
# normalise line endings or Windows and Linux would disagree.
normalize_nl(x::AbstractString) = replace(x, "\r\n" => "\n")
normalize_nl(x::AbstractDict) = Dict{String,Any}(k => normalize_nl(v) for (k, v) in x)
normalize_nl(x::AbstractVector) = Any[normalize_nl(v) for v in x]
normalize_nl(x) = x

function load_unit(path::String)
    d = normalize_nl(TOML.parsefile(path))
    sections = [Section(s["title"], s["body"],
                        [Example(e["code"], get(e, "check", true), getstr(e, "caption"), getstr(e, "mode", "repl"), getstr(e, "notice"))
                         for e in get(s, "example", Any[])],
                        [load_question(q) for q in get(s, "question", Any[])]) for s in get(d, "section", Any[])]
    return Unit(d["id"], d["title"], d["track"], getstr(d, "env", "base"), getstr(d, "status", "ready"),
                d["summary"], String.(get(d, "kcs", String[])), String.(get(d, "prerequisites", String[])),
                String.(get(d, "outline", String[])), String.(get(d, "lessons", String[])), sections,
                [load_problem(p) for p in get(d, "problem", Any[])])
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
end

function load_course_info(path::String)
    d = normalize_nl(TOML.parsefile(path))
    strs(k) = String.(get(d, k, String[]))
    outs = [Outcome(o["text"], String.(get(o, "assessed_by", String[])), String.(get(o, "planned", String[])))
            for o in get(d, "outcome", Any[])]
    return CourseInfo(d["id"], d["title"], Int(d["order"]), getstr(d, "status", "ready"), d["summary"],
                      strs("requires"), strs("envs"), strs("units"), strs("projects"), strs("guided"), outs)
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
        append!(out, [("'$(s.title)' caption", e.caption * "\n" * e.notice) for e in s.examples])
        for q in s.questions
            txt = join(vcat(q.prompt, q.explain, q.misconceptions, q.kind == "choice" ? q.choices : String[]), "\n")
            push!(out, ("'$(s.title)' question", strip_code(txt)))
        end
    end
    for p in u.problems
        push!(out, (p.id, strip_code(join(vcat(p.title, p.prompt, p.hints, [v.label for v in p.variants]), "\n"))))
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
        append!(problems, question_balance_problems(u))
        for s in u.sections, e in s.examples
            isempty(strip(e.code)) && push!(problems, "$(u.id): empty example in '$(s.title)'")
            e.mode in ("repl", "file") || push!(problems, "$(u.id): example mode must be repl or file")
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
        end
    end
    return problems
end

end # module Course
