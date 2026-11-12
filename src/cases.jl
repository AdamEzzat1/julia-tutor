# Scientific case projects (docs/CASES.md): a brief (case.toml) with a real
# question, milestones with hidden acceptance tests, a study the student
# writes, and a report (report.qmd) whose tagged numbers are checked against
# what the student's own study computes.
#
# Untrusted code (the student's package and study) runs only through
# `Practice.child`, with the guided-project driver (src/guided_driver.jl) as
# the program: the sandbox container under `--sandbox=docker`, else a plain
# process for the learner's own code on their own machine. This module reads
# files as text and turns results into feedback with pure functions
# (`parse_report`, `check_report`, `assess`).
#
# What it does not do, said plainly on every check: grade the reasoning.
# The rubric in case.toml is for self-assessment, peers or an instructor.

module Cases

using TOML, Base64
using ..Runner, ..Practice, ..Scaffold, ..Course, ..Guided

export load_case, case_names, validate_case, parse_report, check_report, check, verify_case

const PROJECTS_DIR = normpath(joinpath(@__DIR__, "..", "projects"))

# The eight steps of the method (docs/CASES.md). Each report has one
# level-2 section per step, headed by the title (a longer heading that
# starts with it is fine: "## Verification: is the code right?").
const METHOD_STEPS = [("question", "Question"), ("scales", "Scales and estimate"),
                      ("model", "Model and assumptions"), ("method", "Method choice"),
                      ("verification", "Verification"), ("validation", "Validation"),
                      ("uncertainty", "Uncertainty and sensitivity"), ("report", "Claims and limits")]
const STEP_IDS = first.(METHOD_STEPS)
step_title(id) = METHOD_STEPS[findfirst(s -> s[1] == id, METHOD_STEPS)][2]

const NOT_GRADED = "No software grades the reasoning in your report: the claim checker only checks that each " *
                   "tagged number is what your code computed, that the required evidence is there, and that a " *
                   "clean re-run reproduces it. Judge the argument with the rubric (`tutor case show <case> --rubric`)."

# ---- the brief ---------------------------------------------------------------------------------

struct ClaimSpec
    id::String
    section::String
    kind::String                  # "number" | "word"
    words::Vector{String}
    min_digits::Int
    rtol::Float64
    atol::Float64
    why::String                   # derivation of a nonzero rtol / atol
    text::String
end

struct Evidence
    id::String
    text::String
    claims::Vector{String}
    same_paragraph::Bool
end

struct EstimateSpec
    id::String
    section::String
    compare_with::String
end

struct CaseMilestone
    id::Int
    title::String
    stage::Int
    goal::String
    acceptance::String
    steps::Vector{String}
    report::Bool
end

struct CaseMutant
    id::String
    file::String
    find::String
    replace::String
    description::String
end

struct Case
    name::String
    dir::String                   # projects/<p>/case
    project::String               # the hole project it builds on
    course::String
    env::String
    title::String
    summary::String
    question::String
    qoi::String
    accuracy::String
    emphasised::Vector{String}
    estimate::String
    data::Dict{String,Any}
    milestones::Vector{CaseMilestone}
    tolerance::String
    claims::Vector{ClaimSpec}
    evidence::Vector{Evidence}
    estimates::Vector{EstimateSpec}
    robustness::Dict{String,Any}
    discussion::Vector{Dict{String,Any}}
    rubric::Vector{Dict{String,Any}}
    pilot::Dict{String,Any}
    mutants::Vector{CaseMutant}
    behaviours::Dict{String,String}   # acceptance testset name => what it checks
end

strs(d, k) = String.(get(d, k, String[]))
str(d, k, default = "") = String(strip(get(d, k, default)))

"""Case names: every projects/<p>/case/case.toml."""
case_names(dir::String = PROJECTS_DIR) =
    sort!([p for p in readdir(dir) if isfile(joinpath(dir, p, "case", "case.toml"))])

function load_case(name::AbstractString; dir::String = PROJECTS_DIR)
    occursin(r"^[a-z][a-z0-9_-]*$", name) || error("not a case name: $name")
    cdir = joinpath(dir, name, "case")
    isfile(joinpath(cdir, "case.toml")) || error("no case $name (projects/$name/case/case.toml)")
    d = Course.normalize_nl(TOML.parsefile(joinpath(cdir, "case.toml")))
    ms = [CaseMilestone(m["id"], m["title"], m["stage"], str(m, "goal"), m["acceptance"], strs(m, "steps"),
                        get(m, "report", false)) for m in d["milestone"]]
    claims = [ClaimSpec(c["id"], c["section"], get(c, "kind", "number"), strs(c, "words"),
                        get(c, "min_digits", 2), float(get(c, "rtol", 0.0)), float(get(c, "atol", 0.0)),
                        str(c, "why"), str(c, "text")) for c in get(d, "claim", Any[])]
    ev = [Evidence(e["id"], e["text"], strs(e, "claims"), get(e, "same_paragraph", false)) for e in get(d, "evidence", Any[])]
    est = [EstimateSpec(e["id"], e["section"], get(e, "compare_with", "")) for e in get(d, "estimate", Any[]) if e isa AbstractDict]
    muts = [CaseMutant(m["id"], m["file"], m["find"], m["replace"], str(m, "description")) for m in get(d, "mutant", Any[])]
    beh = Dict{String,String}(String(k) => String(strip(v)) for (k, v) in get(d, "behaviours", Dict()))
    # `estimate` is both the brief's prompt (a string) and the [[estimate]] table list in TOML terms:
    # the prompt lives under `estimate_prompt` when both are present.
    prompt = get(d, "estimate_prompt", "")
    return Case(d["name"], cdir, d["project"], d["course"], get(d, "env", "base"), d["title"], d["summary"],
                strip(d["question"]), d["qoi"], d["accuracy"], strs(d, "emphasised"), String(strip(prompt)),
                get(d, "data", Dict{String,Any}()), ms, get(get(d, "report", Dict()), "tolerance", ""), claims, ev, est,
                get(d, "robustness", Dict{String,Any}()), Dict{String,Any}.(get(d, "discussion", Any[])),
                Dict{String,Any}.(get(d, "rubric", Any[])), get(d, "pilot", Dict{String,Any}()), muts, beh)
end

hole_project(c::Case) = Scaffold.load_project(joinpath(PROJECTS_DIR, c.project))
reference_study(c::Case) = joinpath(c.dir, "reference", "study.jl")
reference_report(c::Case) = joinpath(c.dir, "reference", "report.qmd")
template_dir(c::Case) = joinpath(c.dir, "template")
claim(c::Case, id) = (i = findfirst(x -> x.id == id, c.claims); i === nothing ? nothing : c.claims[i])

const EM_DASH = Char(0x2014)

"""Filler phrases and em dashes in the brief's prose (the course's house rules)."""
function prose_problems(c::Case)
    texts = Tuple{String,String}[("summary", c.summary), ("question", c.question), ("qoi", c.qoi),
                                 ("accuracy", c.accuracy), ("estimate prompt", c.estimate)]
    append!(texts, [("milestone $(m.id)", m.title * "\n" * m.goal) for m in c.milestones])
    append!(texts, [("discussion $i", get(q, "text", "")) for (i, q) in enumerate(c.discussion)])
    append!(texts, [("rubric $(get(r, "step", "?"))", join(vcat(get(r, "criterion", ""), get(r, "levels", String[])), "\n"))
                    for r in c.rubric])
    append!(texts, [("behaviour $k", v) for (k, v) in c.behaviours])
    out = String[]
    for (where, txt) in texts
        low = lowercase(Course.strip_code(txt))
        for w in Course.FILLER
            occursin(Regex("(?<![\\w-])\\Q" * w * "\\E(?![\\w-])"), low) && push!(out, "$where: filler phrase \"$w\"")
        end
        occursin(EM_DASH, txt) && push!(out, "$where: em dash (use a colon, comma or parentheses)")
    end
    return sort!(out)
end

"""Structural problems of a case (no Julia run needed). Empty = valid."""
function validate_case(c::Case)
    out = String[]
    isempty(strip(c.question)) && push!(out, "no question")
    isempty(strip(c.qoi)) && push!(out, "no quantity of interest")
    isempty(strip(c.accuracy)) && push!(out, "no required accuracy")
    isempty(strip(c.estimate)) && push!(out, "no estimate prompt (`estimate_prompt`)")
    for s in c.emphasised
        s in STEP_IDS || push!(out, "emphasised step $s is not one of $(STEP_IDS)")
    end
    isempty(c.emphasised) && push!(out, "no emphasised method steps")
    isempty(strip(get(c.data, "kind", ""))) && push!(out, "data: no kind")
    isempty(strip(get(c.data, "description", ""))) && push!(out, "data: no description (provenance, generator or ground truth)")
    p = try hole_project(c) catch e; push!(out, "hole project $(c.project): $(sprint(showerror, e))"); nothing end
    [m.id for m in c.milestones] == collect(1:length(c.milestones)) || push!(out, "milestones must be numbered 1, 2, ...")
    for m in c.milestones
        isfile(joinpath(c.dir, m.acceptance)) || push!(out, "milestone $(m.id): no $(m.acceptance)")
        p === nothing || m.stage in p.stages || push!(out, "milestone $(m.id): stage $(m.stage) is not a stage of $(c.project)")
        all(in(STEP_IDS), m.steps) || push!(out, "milestone $(m.id): unknown method step in $(m.steps)")
    end
    count(m -> m.report, c.milestones) == 1 || push!(out, "exactly one milestone carries the report")
    isempty(strip(c.tolerance)) && push!(out, "[report] tolerance: say where the claim tolerance comes from")
    ids = [x.id for x in c.claims]
    allunique(ids) || push!(out, "claim ids are not unique")
    for x in c.claims
        x.section in STEP_IDS || push!(out, "claim $(x.id): section $(x.section) is not a method step")
        x.kind in ("number", "word") || push!(out, "claim $(x.id): kind must be number or word")
        x.kind == "word" && isempty(x.words) && push!(out, "claim $(x.id): a word claim lists its words")
        x.min_digits >= 1 || push!(out, "claim $(x.id): min_digits must be >= 1")
        (x.rtol > 0 || x.atol > 0) && isempty(x.why) &&
            push!(out, "claim $(x.id): a nonzero tolerance needs its derivation in `why` (invariant 9)")
        isempty(x.text) && push!(out, "claim $(x.id): no text")
    end
    for e in c.evidence, id in e.claims
        id in ids || push!(out, "evidence $(e.id): unknown claim $id")
    end
    for e in c.estimates
        e.section in STEP_IDS || push!(out, "estimate $(e.id): unknown section $(e.section)")
        isempty(e.compare_with) || e.compare_with in ids || push!(out, "estimate $(e.id): unknown claim $(e.compare_with)")
    end
    isempty(c.estimates) && push!(out, "no [[estimate]]: the scales step commits an estimate before computing")
    for k in ("assumption", "perturbed")
        isempty(strip(get(c.robustness, k, ""))) && push!(out, "robustness: no $k")
    end
    rc = String.(get(c.robustness, "claims", String[]))
    isempty(rc) && push!(out, "robustness: no claims")
    foreach(id -> id in ids || push!(out, "robustness: unknown claim $id"), rc)
    for (i, q) in enumerate(c.discussion)
        k = get(q, "kind", "")
        k in ("prediction", "rubric") || push!(out, "discussion $i: kind must be prediction or rubric")
        k == "prediction" && !(get(q, "measured_by", "") in ids) &&
            push!(out, "discussion $i: a prediction names the claim that measures it (`measured_by`)")
    end
    for s in STEP_IDS
        any(r -> get(r, "step", "") == s, c.rubric) || push!(out, "rubric: no criterion for step $s")
    end
    for r in c.rubric
        length(get(r, "levels", String[])) == 3 || push!(out, "rubric $(get(r, "step", "?")): needs 3 levels")
    end
    isempty(strip(get(c.pilot, "status", ""))) && push!(out, "pilot: no status")
    for f in (reference_study(c), reference_report(c), joinpath(template_dir(c), "study.jl"), joinpath(template_dir(c), "report.qmd"))
        isfile(f) || push!(out, "missing $(relpath(f, c.dir))")
    end
    if isfile(reference_study(c))
        src = read(reference_study(c), String)
        for m in c.mutants
            m.file == "study.jl" || push!(out, "mutant $(m.id): only study.jl mutants are supported")
            n = length(findall(m.find, src))
            n == 1 || push!(out, "mutant $(m.id): the snippet occurs $n times in the reference study (must be 1)")
        end
    end
    rm_ = findfirst(m -> m.report, c.milestones)
    if rm_ !== nothing && isfile(joinpath(c.dir, c.milestones[rm_].acceptance))
        acc = read(joinpath(c.dir, c.milestones[rm_].acceptance), String)
        for id in ids
            occursin("\"$id\"", acc) || push!(out, "claim $id: the report milestone's acceptance tests never mention it")
        end
    end
    append!(out, prose_problems(c))
    return out
end

# ---- the report ------------------------------------------------------------------------------

struct Tag
    kind::Symbol                  # :claim | :estimate
    id::String
    value::Union{Nothing,String}
    line::Int
    step::Union{Nothing,String}   # method step of the enclosing section
    paragraph::Int
end

struct ReportParse
    sections::Vector{Tuple{String,Int}}      # (step id, line) of each recognised section heading
    tags::Vector{Tag}
end

const TAG_RE = r"\{(claim|estimate):([A-Za-z0-9_]+)\}"
const VALUE_RE = r"([-+]?(?:\d[\d.]*)(?:[eE][-+]?\d+)?|[A-Za-z][A-Za-z0-9_-]*) ?$"

"""The method step a level-2 heading names, or `nothing`."""
function heading_step(title::AbstractString)
    t = lowercase(strip(title))
    for (id, name) in METHOD_STEPS
        startswith(t, lowercase(name)) && return id
    end
    return nothing
end

"""
    parse_report(text) -> ReportParse

Sections (level-2 headings naming a method step) and tags. A tag's value is
the number or word written right before it (one space allowed). Fenced code
blocks, inline code, HTML comments and the YAML header are skipped: a tag in
code or a comment is not a claim. Paragraphs are separated by blank lines
and headings. Line numbers are those of the file.
"""
function parse_report(text::AbstractString)
    text = replace(String(text), "\r\n" => "\n")
    # Comments become as many newlines as they span (line numbers stay right).
    text = replace(text, r"<!--.*?-->"s => m -> "\n"^count(==('\n'), m))
    lines = split(text, '\n')
    sections = Tuple{String,Int}[]
    tags = Tag[]
    step = nothing
    para = 1
    infence = false
    inyaml = !isempty(lines) && strip(lines[1]) == "---"
    for (i, l) in enumerate(lines)
        s = strip(l)
        if inyaml
            i > 1 && s in ("---", "...") && (inyaml = false)
            continue
        end
        if startswith(s, "```") || startswith(s, "~~~")
            infence = !infence
            continue
        end
        infence && continue
        if isempty(s)
            para += 1
            continue
        end
        if startswith(s, "## ")
            step = heading_step(s[4:end])
            step === nothing || push!(sections, (step, i))
            para += 1
            continue
        elseif startswith(s, "# ")
            step = nothing
            para += 1
            continue
        end
        # Inline code becomes spaces, so a value written as code is no value
        # (after the fence test above: a fence's ``` is not inline code).
        l = replace(l, r"`[^`\n]*`" => m -> " "^length(m))
        for m in eachmatch(TAG_RE, l)
            prefix = l[1:prevind(l, m.offset)]
            v = match(VALUE_RE, prefix)
            value = v === nothing ? nothing : String(v[1])
            push!(tags, Tag(Symbol(m[1]), m[2], value, i, step, para))
        end
    end
    return ReportParse(sections, tags)
end

struct Finding
    line::Int
    code::String
    message::String
end

"""
Significant digits and the decimal place of the last digit of a written
number ("5.18" -> (3, -2); "3.9e-3" -> (2, -4); "1000" -> (4, 0)).
"""
function written_precision(w::AbstractString)
    s = lstrip(w, ['+', '-'])
    mant, ex = occursin(r"[eE]", s) ? split(s, r"[eE]"; limit = 2) : (s, "0")
    e = parse(Int, ex)
    frac = occursin('.', mant) ? length(split(mant, '.')[2]) : 0
    digits = lstrip(filter(isdigit, mant), '0')
    return (max(length(digits), 1), e - frac)
end

is_integer_literal(w::AbstractString) = occursin(r"^[-+]?\d+$", w)

"""
    match_value(spec, written, computed) -> (code or nothing, detail)

The tolerance rule of `[report] tolerance` in case.toml: a number matches
when |w - c| <= max(0.5 * 10^k, rtol * |c|, atol), k the decimal place of
the last written digit; an integer written without a point must be exact;
fewer than `min_digits` significant digits is too coarse unless w == c.
Words match case-insensitively.
"""
function match_value(spec::ClaimSpec, w::AbstractString, c)
    if spec.kind == "word"
        cw = lowercase(string(c))
        lowercase(w) in lowercase.(spec.words) || return ("claim-mismatch", "`$w` is not one of $(join(spec.words, ", "))")
        return lowercase(w) == cw ? (nothing, "") : ("claim-mismatch", "you wrote `$w`; your study() computed `$c`")
    end
    c isa Real || return ("claim-mismatch", "your study() returned `$c`, not a number")
    x = tryparse(Float64, w)
    x === nothing && return ("claim-no-value", "`$w` is not a number")
    cf = Float64(c)
    isequal(x, cf) && return (nothing, "")
    if is_integer_literal(w)
        return ("claim-mismatch", "you wrote $w; your study() computed $(repr(c)) (an integer written without a decimal point must be exact)")
    end
    digits, k = written_precision(w)
    digits < spec.min_digits && return ("claim-too-coarse", "$w has $digits significant digit(s); write at least $(spec.min_digits)")
    tol = max(0.5 * 10.0^k, spec.rtol * abs(cf), spec.atol)
    # The 1e-9 relative slack covers the decimal-to-binary conversion of w
    # (<= 1 ulp), which only matters exactly at the boundary.
    abs(x - cf) <= tol * (1 + 1e-9) && return (nothing, "")
    return ("claim-mismatch", "you wrote $w; your study() computed $(repr(cf)) (match within $(tol))")
end

"""
    check_report(c, text, values; rerun = nothing) -> (findings, estimates)

Pure. `values` is what the student's `study()` returned (claim id =>
value); `rerun` the same from a second clean run. `estimates` lists
(id, written, compared claim, computed) for display; estimates are never
graded.
"""
function check_report(c::Case, text::AbstractString, values::AbstractDict; rerun = nothing)
    r = parse_report(text)
    out = Finding[]
    found = Set(first.(r.sections))
    for (id, title) in METHOD_STEPS
        id in found || push!(out, Finding(0, "section-missing", "no `## $title` section"))
    end
    claimed = Dict{String,Vector{Tag}}()
    for t in r.tags
        t.kind === :claim || continue
        push!(get!(claimed, t.id, Tag[]), t)
        spec = claim(c, t.id)
        if spec === nothing
            push!(out, Finding(t.line, "claim-unknown", "{claim:$(t.id)} is not a claim of this case"))
        elseif t.value === nothing
            push!(out, Finding(t.line, "claim-no-value", "{claim:$(t.id)}: write the value right before the tag " *
                                                         "(the checker does not run inline code)"))
        elseif !haskey(values, t.id)
            push!(out, Finding(t.line, "claim-not-computed", "{claim:$(t.id)}: your study() does not return \"$(t.id)\""))
        else
            code, detail = match_value(spec, t.value, values[t.id])
            code === nothing || push!(out, Finding(t.line, code, "{claim:$(t.id)}: $detail"))
        end
        if rerun !== nothing && haskey(values, t.id) &&
           !(haskey(rerun, t.id) && isequal(values[t.id], rerun[t.id]))
            push!(out, Finding(t.line, "not-reproducible", "{claim:$(t.id)}: a clean re-run of study() gave " *
                                                           "$(repr(get(rerun, t.id, "nothing"))), not $(repr(values[t.id]))"))
        end
    end
    for spec in c.claims
        ts = get(claimed, spec.id, Tag[])
        if isempty(ts)
            push!(out, Finding(0, "claim-missing", "no {claim:$(spec.id)} ($(spec.text)); it belongs in `## $(step_title(spec.section))`"))
        elseif !any(t -> t.step == spec.section, ts)
            push!(out, Finding(first(ts).line, "claim-wrong-section",
                               "{claim:$(spec.id)} must be stated (at least once) in `## $(step_title(spec.section))`"))
        end
    end
    for e in c.evidence
        missing_ = [id for id in e.claims if !haskey(claimed, id)]
        if !isempty(missing_)
            push!(out, Finding(0, "evidence-missing", "required evidence: $(e.text) (missing: $(join(missing_, ", ")))"))
        elseif e.same_paragraph
            paras = [Set(t.paragraph for t in claimed[id]) for id in e.claims]
            isempty(intersect(paras...)) &&
                push!(out, Finding(minimum(t.line for id in e.claims for t in claimed[id]), "evidence-split",
                                   "required evidence: $(e.text): state $(join(e.claims, ", ")) in one paragraph"))
        end
    end
    estimates = Tuple{String,String,String,Any}[]
    for e in c.estimates
        ts = [t for t in r.tags if t.kind === :estimate && t.id == e.id && t.step == e.section && t.value !== nothing &&
                                   tryparse(Float64, t.value) !== nothing]
        if isempty(ts)
            push!(out, Finding(0, "estimate-missing", "no {estimate:$(e.id)} with a number in `## $(step_title(e.section))`"))
        else
            push!(estimates, (e.id, first(ts).value, e.compare_with, get(values, e.compare_with, nothing)))
        end
    end
    sort!(out; by = f -> (f.line, f.code, f.message))
    return out, estimates
end

# ---- running student code in the sandbox -------------------------------------------------------

"""
The study's include line, prepended (on the host, as text) to every test
file that needs the study. Only one implementation directory is on disk
next to `acceptance/` while a run executes (src/guided_driver.jl), so it is
found by listing the parent directory.
"""
const STUDY_INCLUDE = """
let impl = only(filter(d -> d != "acceptance", readdir(joinpath(@__DIR__, ".."))))
    include(joinpath(@__DIR__, "..", impl, "study", "study.jl"))
end
"""

"""The claims runner: calls study() and writes claims.toml (exact bits for floats) next to the result."""
const CLAIMS_RUNNER = STUDY_INCLUDE * raw"""
using Test, TOML
const CASE_OUT_DIR = pwd()
function encode_claim(v)
    v isa Bool && return Dict("kind" => "word", "value" => string(v))
    v isa Integer && return Dict("kind" => "int", "value" => Int(v))
    v isa AbstractFloat && return Dict("kind" => "float", "value" => Float64(v),
                                       "bits" => string(reinterpret(UInt64, Float64(v)); base = 16))
    v isa Union{AbstractString,Symbol} && return Dict("kind" => "word", "value" => string(v))
    return Dict("kind" => "other", "value" => first(repr(v), 200))
end
@testset "claims" begin
    vals = study()
    cd(CASE_OUT_DIR)
    @test vals isa AbstractDict
    out = Dict{String,Any}(string(k) => encode_claim(v) for (k, v) in vals)
    open(io -> TOML.print(io, out; sorted = true), joinpath(CASE_OUT_DIR, "claims.toml"), "w")
end
"""

decode_claim(d) = d["kind"] == "float" ? reinterpret(Float64, parse(UInt64, d["bits"]; base = 16)) :
                  d["kind"] == "int" ? Int(d["value"]) : String(string(d["value"]))
decode_claims(d::AbstractDict) = Dict{String,Any}(k => decode_claim(v) for (k, v) in d)

"""Files of a student's case directory the checker sends: src/**.jl and study/study.jl, as text."""
function student_files(dir::AbstractString)
    out = Dict{String,String}()
    for sub in ("src", "study"), (root, _, fs) in walkdir(joinpath(dir, sub)), f in fs
        endswith(f, ".jl") || continue
        rel = replace(relpath(joinpath(root, f), dir), '\\' => '/')
        out[rel] = read(joinpath(root, f), String)
    end
    return out
end

prefix(files, p) = Dict(p * "/" * k => v for (k, v) in files)

"""Acceptance files for milestones 1..m (the report milestone's gets the study include)."""
function acceptance_files(c::Case, m::Int)
    out = Dict{String,String}()
    for x in c.milestones
        x.id <= m || continue
        src = read(joinpath(c.dir, x.acceptance), String)
        out["acceptance/m$(x.id).jl"] = x.report ? STUDY_INCLUDE * src : src
    end
    return out
end

"""A job for the guided driver: `impls` maps an implementation label to its files."""
function make_job(c::Case, impls::Vector{Pair{String,Dict{String,String}}}, runs::Vector{Pair{String,Int}};
                  claims::Bool = false)
    p = hole_project(c)
    m = maximum(last.(runs); init = 0)
    files = acceptance_files(c, m)
    claims && (files["acceptance/claims.jl"] = CLAIMS_RUNNER)
    rs = Any[]
    for (label, impl) in impls
        merge!(files, prefix(impl, label))
    end
    for (label, k) in runs
        for x in c.milestones
            x.id <= k || continue
            push!(rs, Dict("label" => "$label acceptance m$(x.id)", "impl" => label, "tests" => "acceptance/m$(x.id).jl"))
        end
    end
    claims && append!(rs, [Dict("label" => "$label claims", "impl" => label, "tests" => "acceptance/claims.jl")
                           for (label, _) in impls])
    sort!(rs; by = r -> r["impl"])            # the driver groups runs by implementation
    return Dict("package" => p.package, "seed" => Guided.SEED, "files" => files, "runs" => rs)
end

"""Run a job in the sandbox. Returns (raw result or nothing, claims or nothing, timed_out, log)."""
function run_job(c::Case, job; timeout::Real = 1200)
    dir = mktempdir()
    path = joinpath(dir, "main.jl")
    write(path, Guided.driver_source(job))
    _, to, log = Practice.child(["run", path, "file"], dir; env = c.env, timeout)
    raw = isfile(joinpath(dir, "result.toml")) ? TOML.parsefile(joinpath(dir, "result.toml")) : nothing
    cl = isfile(joinpath(dir, "claims.toml")) ? decode_claims(TOML.parsefile(joinpath(dir, "claims.toml"))) : nothing
    try rm(dir; recursive = true, force = true) catch end
    return raw, cl, to, Practice.clip(log, 20_000)
end

# ---- assessing a check -------------------------------------------------------------------------

run_ok(r) = !haskey(r, "load_error") && !get(r, "tests_missing", false) && isempty(get(r, "toplevel_error", "")) &&
            get(r, "total", 0) > 0 && all(s -> s["failed"] == 0 && s["errored"] == 0, get(r, "testsets", Any[]))

"""Failing testsets of one run, as (name, detail) for the student (never the test code)."""
function failures(r)
    haskey(r, "load_error") && return [("load", "your package does not load: " * r["load_error"])]
    get(r, "tests_missing", false) && return [("load", "the acceptance file did not run")]
    out = Tuple{String,String}[]
    isempty(get(r, "toplevel_error", "")) || push!(out, ("top level", r["toplevel_error"]))
    for s in get(r, "testsets", Any[])
        (s["failed"] == 0 && s["errored"] == 0) && continue
        isempty(s["name"]) && continue
        push!(out, (s["name"], isempty(s["errors"]) ? "$(s["failed"]) check(s) failed" : first(s["errors"])))
    end
    return out
end

"""
    assess(c, m, raw, values, rerun, report; timed_out, log) -> (passed, text)

Pure: from the driver's results to the check's verdict and text.
"""
function assess(c::Case, m::Int, raw, values, rerun, report::Union{Nothing,String}; timed_out::Bool = false, log = "")
    io = IOBuffer()
    println(io, "== tutor case check: $(c.name), milestone $m ==")
    println(io)
    if raw === nothing
        println(io, timed_out ? "The check timed out." : "The check did not run to the end.")
        isempty(strip(log)) || println(io, "  ", first(split(strip(log), '\n')))
        return false, String(take!(io))
    end
    passed = get(raw, "complete", false)
    for x in c.milestones
        x.id <= m || continue
        r = Guided.run_by(raw, "student acceptance m$(x.id)")
        if r === nothing
            println(io, "Acceptance m$(x.id): did not run"); passed = false; continue
        end
        if run_ok(r)
            println(io, "Acceptance m$(x.id): all $(length(filter(s -> !isempty(s["name"]), r["testsets"]))) behaviours pass")
        else
            passed = false
            fs = failures(r)
            println(io, "Acceptance m$(x.id): $(length(fs)) failing")
            for (name, detail) in fs
                println(io, "  FAIL $name: ", get(c.behaviours, name, ""))
                println(io, "       ", first(split(detail, '\n')))
            end
        end
    end
    mr = c.milestones[m]
    if mr.report
        println(io)
        if values === nothing
            passed = false
            println(io, "Study: study() did not return its values (see the acceptance results above).")
        else
            same = rerun !== nothing && all(k -> haskey(rerun, k) && isequal(values[k], rerun[k]), keys(values))
            println(io, "Study: ran twice in fresh processes, $(length(values)) values; " *
                        (same ? "the re-run reproduced every value" : "the re-run did NOT reproduce every value"))
            same || (passed = false)
            if report === nothing
                passed = false
                println(io, "Report: no report.qmd")
            else
                findings, estimates = check_report(c, report, values; rerun)
                println(io, "Report (report.qmd): ", isempty(findings) ? "every claim checked, no findings" : "$(length(findings)) finding(s)")
                for f in findings
                    println(io, "  ", f.line == 0 ? "" : "line $(f.line): ", f.code, ": ", f.message)
                end
                isempty(findings) || (passed = false)
                if !isempty(estimates)
                    println(io, "Estimates (never graded; your estimate next to what you measured):")
                    for (id, w, cw, v) in estimates
                        println(io, "  $id: you estimated $w", isempty(cw) ? "" : "; you measured $cw = $(v === nothing ? "?" : v)")
                    end
                end
            end
        end
        println(io)
        println(io, NOT_GRADED)
    end
    println(io)
    println(io, "Milestone $m: ", passed ? "passed" : "not passed")
    return passed, String(take!(io))
end

"""
    check(c, dir, m; timeout) -> (passed, text)

Run milestone `m`'s check on a student directory (a starter from `tutor
start` / `tutor case start`): acceptance tests of milestones 1..m on the
student's package (and study), and for the report milestone two clean runs
of study() and the claim checker on report.qmd.
"""
function check(c::Case, dir::AbstractString, m::Int; timeout::Real = 1200)
    1 <= m <= length(c.milestones) || error("milestone must be 1 to $(length(c.milestones))")
    files = student_files(dir)
    rep = c.milestones[m].report
    job = make_job(c, ["student" => files], ["student" => m]; claims = rep)
    raw, values, to, log = run_job(c, job; timeout)
    rerun = nothing
    if rep && values !== nothing
        _, rerun, _, _ = run_job(c, make_job(c, ["student" => files], Pair{String,Int}[]; claims = true); timeout)
    end
    report = rep && isfile(joinpath(dir, "report.qmd")) ? read(joinpath(dir, "report.qmd"), String) : nothing
    return assess(c, m, raw, values, rerun, report; timed_out = to, log)
end

# ---- authoring self-test -------------------------------------------------------------------------

"""The reference implementation as a student directory's files."""
function reference_files(c::Case)
    p = hole_project(c)
    out = Dict{String,String}()
    for rel in Scaffold.package_files(p)
        startswith(rel, "src/") && endswith(rel, ".jl") || continue
        out[rel] = Scaffold.render_source(read(joinpath(Scaffold.reference_dir(p), rel), String), rel, Dict{String,String}())
    end
    out["study/study.jl"] = read(reference_study(c), String)
    return out
end

"""Report fixtures: (name, text, rerun perturbation, expected codes) from case/report_fixtures.toml."""
function report_fixtures(c::Case)
    path = joinpath(c.dir, "report_fixtures.toml")
    isfile(path) || return Any[]
    base = replace(read(reference_report(c), String), "\r\n" => "\n")   # a CRLF checkout must not move a snippet
    out = Any[]
    for f in TOML.parsefile(path)["fixture"]
        text = base
        for (a, b) in zip(String.(get(f, "find", String[])), String.(get(f, "replace", String[])))
            occursin(a, text) || error("report fixture $(f["name"]): snippet not found: $a")
            text = replace(text, a => b; count = 1)
        end
        push!(out, (f["name"], text, get(f, "rerun_differs", ""), sort!(unique(String.(f["expect"])))))
    end
    return out
end

"""
    verify_case(c; log) -> problems

The authoring self-test (docs/CASES.md): the brief is valid; the reference
passes every milestone's acceptance tests and its study is reproducible;
the reference report has no findings; each report fixture gets exactly its
declared findings; every hole trivial body (holes.toml) fails the hidden
acceptance tests of its stage's milestone, and every study mutant fails the
report milestone's; every acceptance testset has its prose.
"""
function verify_case(c::Case; log = stdout, timeout::Real = 3600)
    problems = validate_case(c)
    isempty(problems) || return problems
    p = hole_project(c)
    ref = reference_files(c)
    nm = length(c.milestones)
    rm_ = findfirst(x -> x.report, c.milestones)
    impls = Pair{String,Dict{String,String}}["reference" => ref]
    runs = Pair{String,Int}["reference" => nm]
    expect = Dict{String,String}()              # impl label => what it is
    k = 0
    for h in p.holes, (i, body) in enumerate(h.trivial_bodies)
        ms = findfirst(x -> x.stage == h.stage, c.milestones)   # the milestone that first opens this hole
        ms === nothing && continue
        files = copy(ref)
        files[h.file] = Scaffold.render_source(read(joinpath(Scaffold.reference_dir(p), h.file), String), h.file,
                                               Dict(h.id => body))
        k += 1
        label = "impl_$(lpad(k, 3, '0'))"
        push!(impls, label => files); push!(runs, label => c.milestones[ms].id)
        expect[label] = "trivial body $i of hole $(h.id) (milestone $(c.milestones[ms].id))"
    end
    for x in c.mutants
        files = copy(ref)
        files["study/study.jl"] = replace(files["study/study.jl"], x.find => x.replace; count = 1)
        k += 1
        label = "impl_$(lpad(k, 3, '0'))"
        push!(impls, label => files); push!(runs, label => c.milestones[rm_].id)
        expect[label] = "study mutant $(x.id)"
    end
    println(log, "running the reference and $(k) mutants of $(c.name) in one sandboxed process...")
    t0 = time()
    raw, values, to, lg = run_job(c, make_job(c, impls, runs; claims = false); timeout)
    println(log, "  done in $(round(time() - t0; digits = 1)) s")
    raw === nothing && return ["the verify job did not finish" * (to ? " (timed out)" : "") * ": " * first(split(strip(lg) * "\n", '\n'))]
    get(raw, "complete", false) || push!(problems, "the verify job did not run to the end")
    for x in c.milestones
        r = Guided.run_by(raw, "reference acceptance m$(x.id)")
        r === nothing && (push!(problems, "reference: milestone $(x.id) did not run"); continue)
        run_ok(r) || push!(problems, "reference fails milestone $(x.id): " * join(["$a ($b)" for (a, b) in failures(r)], "; "))
        for s in r["testsets"]
            isempty(s["name"]) || haskey(c.behaviours, s["name"]) ||
                push!(problems, "acceptance m$(x.id) testset `$(s["name"])` has no prose in [behaviours]")
        end
    end
    for (label, what) in sort!(collect(expect))
        rs = [r for r in raw["runs"] if r["impl"] == label]
        isempty(rs) && (push!(problems, "$what: did not run"); continue)
        all(run_ok, rs) && push!(problems, "$what passes the hidden acceptance tests (mutant survived)")
    end
    # The reference study, twice, in fresh processes; the reference report against it.
    claims_job = make_job(c, ["reference" => ref], Pair{String,Int}[]; claims = true)
    t0 = time()
    _, v1, _, lg1 = run_job(c, claims_job; timeout)
    _, v2, _, _ = run_job(c, claims_job; timeout)
    println(log, "  reference study, two clean runs: $(round(time() - t0; digits = 1)) s")
    v1 === nothing && return push!(problems, "reference study() did not run: " * first(split(strip(lg1) * "\n", '\n')))
    v2 !== nothing && all(k -> haskey(v2, k) && isequal(v1[k], v2[k]), keys(v1)) ||
        push!(problems, "the reference study is not reproducible")
    findings, _ = check_report(c, read(reference_report(c), String), v1; rerun = v2)
    for f in findings
        push!(problems, "reference report line $(f.line): $(f.code): $(f.message)")
    end
    for (name, text, differs, want) in report_fixtures(c)
        rr = copy(v1)
        isempty(differs) || (rr[differs] = v1[differs] isa AbstractFloat ? nextfloat(v1[differs]) : "changed")
        fs, _ = check_report(c, text, v1; rerun = rr)
        got = sort!(unique([f.code for f in fs]))
        got == want || push!(problems, "report fixture $name: findings $(got), expected $(want)")
    end
    println(log, "  $(length(report_fixtures(c))) report fixtures, $(k) mutants checked")
    return problems
end

# ---- the brief as text, the student's folder, the site page ------------------------------------

mdcell(s) = replace(strip(s), "|" => "\\|", "\n" => " ")
oneline(s) = replace(strip(s), r"\s*\n\s*" => " ")

"""
The brief in Markdown, generated from case.toml: `tutor case show`, the
student's BRIEF.md and the site page are this text, so they cannot drift.
`rubric = false` leaves the rubric out (for `show` without `--rubric`).
"""
function brief_markdown(c::Case; rubric::Bool = true, heading::Int = 2)
    h = "#"^heading
    io = IOBuffer()
    println(io, c.summary, "\n")
    println(io, "$h The question\n")
    println(io, oneline(c.question), "\n")
    println(io, "* **Quantity of interest:** ", oneline(c.qoi))
    println(io, "* **Required accuracy:** ", oneline(c.accuracy))
    println(io, "* **Steps of the method this case stresses:** ", join([step_title(s) for s in c.emphasised], ", "),
            ". The report has a section for each of the eight: ", join([t for (_, t) in METHOD_STEPS], ", "), ".")
    println(io, "* **Estimate first:** ", oneline(c.estimate), "\n")
    println(io, "$h Data\n")
    println(io, "Kind: ", get(c.data, "kind", ""), ". ", oneline(get(c.data, "description", "")), "\n")
    diffs = get(c.data, "difficulty", Any[])
    if !isempty(diffs)
        println(io, "Difficulties built in on purpose, each tied to a knowledge component:\n")
        for d in diffs
            println(io, "* ", oneline(d["what"]), " (`", d["kc"], "`)")
        end
        println(io)
    end
    println(io, "$h Milestones\n")
    for m in c.milestones
        println(io, "$(m.id). **", m.title, ".** ", oneline(m.goal),
                " Method steps: ", join([step_title(s) for s in m.steps], ", "), ".")
    end
    println(io)
    println(io, "$h What is checked, and what is not\n")
    println(io, "Checked by software, deterministically, in the sandbox on your machine:\n")
    println(io, "* each milestone's hidden acceptance tests (failures name the behaviour, never the test code);")
    println(io, "* in the report, every number tagged `{claim:<id>}` must equal what your own `study()` computed, ",
            "to half a unit in the last digit you wrote (", c.tolerance, ");")
    println(io, "* the required evidence is present (below), and a clean re-run of `study()` reproduces every claimed value bit for bit.\n")
    println(io, "**Not checked by any software: the quality of your scientific argument.** ",
            "No program grades the reasoning. Use the rubric below to judge it yourself, with a peer, or with an instructor.\n")
    println(io, "Required evidence:\n")
    for e in c.evidence
        println(io, "* ", e.text, ": ", join(["`$x`" for x in e.claims], ", "), e.same_paragraph ? " (in one paragraph)" : "")
    end
    println(io)
    println(io, "Robustness: ", oneline(get(c.robustness, "assumption", "")), " is re-checked under ",
            oneline(get(c.robustness, "perturbed", "")), "; the report says whether the conclusion still holds.\n")
    println(io, "| claim | section | what it is |")
    println(io, "|---|---|---|")
    for x in c.claims
        println(io, "| `", x.id, "` | ", step_title(x.section), " | ", mdcell(x.text), x.kind == "word" ? " (one of: $(join(x.words, ", ")))" : "", " |")
    end
    println(io)
    println(io, "$h Discussion questions\n")
    for (i, q) in enumerate(c.discussion)
        tag = get(q, "kind", "") == "prediction" ? "prediction (measured; it will be graded as a prediction once predictions exist)" :
              "for discussion, judged with the rubric"
        println(io, "$i. ", oneline(q["text"]), " *(", tag, ")*")
    end
    println(io)
    if rubric
        println(io, "$h Rubric\n")
        println(io, "For self-assessment, peer review or an instructor. It rewards supported claims; ",
                "length, code volume and the number of plots earn nothing.\n")
        println(io, "| step | criterion | 0 | 1 | 2 |")
        println(io, "|---|---|---|---|---|")
        for r in c.rubric
            lv = get(r, "levels", String[])
            println(io, "| ", step_title(r["step"]), " | ", mdcell(r["criterion"]), " | ", join(mdcell.(lv), " | "), " |")
        end
        println(io)
    end
    println(io, "$h Pilot\n")
    println(io, "Status: **", get(c.pilot, "status", ""), "**. Nothing here is evidence that the case teaches well until it has run. It needs:\n")
    for n in get(c.pilot, "needs", String[])
        println(io, "* ", oneline(n))
    end
    println(io)
    println(io, "$h Commands\n")
    println(io, "```")
    println(io, "tutor start $(c.project) 1 work/m1        # milestone 1: the stage-1 holes")
    println(io, "tutor explain $(c.project) work/m1        # tests, findings, where to start")
    println(io, "tutor case check work/m1 1               # milestone 1's hidden acceptance tests")
    println(io, "tutor case start $(c.name) work/case      # milestones 2 and 3: all holes, study.jl, report.qmd")
    println(io, "tutor case check work/case 2")
    println(io, "tutor case check work/case 3             # acceptance, two clean runs of study(), the claim checker")
    println(io, "```")
    return String(take!(io))
end

"""The student's folder for the last stage: the hole starter, the study and report templates, the brief."""
function start_files(c::Case)
    p = hole_project(c)
    files = Scaffold.starter_files(p, maximum(p.stages))
    files["study/study.jl"] = read(joinpath(template_dir(c), "study.jl"), String)
    files["report.qmd"] = read(joinpath(template_dir(c), "report.qmd"), String)
    files["BRIEF.md"] = "# " * c.title * "\n\n" * brief_markdown(c)
    files[".tutor-case.toml"] = "# generated by tutor case start\ncase = \"$(c.name)\"\n"
    return files
end

"""The case a student folder belongs to: .tutor-case.toml, or the hole project of a `tutor start` folder."""
function case_of(dir::AbstractString)
    for (f, k) in ((".tutor-case.toml", "case"), (".tutor-project.toml", "project"))
        path = joinpath(dir, f)
        isfile(path) || continue
        name = get(TOML.parsefile(path), k, "")
        name in case_names() && return load_case(name)
    end
    return nothing
end

site_page_path(c::Case) = normpath(joinpath(PROJECTS_DIR, "..", "site", "case-$(c.name).qmd"))

"""The site page (site/case-<name>.qmd), generated: `tutor case site [--check]`."""
function site_page(c::Case)
    io = IOBuffer()
    println(io, "---")
    println(io, "title: \"Case: ", replace(c.title, "\"" => "'"), "\"")
    println(io, "subtitle: \"A scientific case project in the ", c.course, " course. Generated from projects/",
            c.project, "/case/case.toml by `tutor case site`; do not edit.\"")
    println(io, "---")
    println(io)
    println(io, "::: {.callout-note}")
    println(io, "This page is the brief. Nothing on it runs in the browser: the checks run on your machine, in the sandbox, ",
            "with `tutor case check`.")
    println(io, ":::")
    println(io)
    print(io, brief_markdown(c))
    return String(take!(io))
end

end # module Cases
