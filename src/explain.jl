# `tutor explain`: joins test failures, static findings, measurements and the
# measured test-to-hole map, and says where to start.
#
# Evidence order when choosing where to start (most certain first):
# 1. a parse error (JT000) or a test run that crashed: nothing else is meaningful;
# 2. holes ranked by Ochiai over the measured test-to-hole map;
#    ties broken by teaching order (holes.toml);
# 3. per hole, attached evidence: TODO errors seen, static findings inside the
#    hole's function, measured inference differences from the reference.

module Explain

using TOML
using JuliaSyntax
const JS = JuliaSyntax
using ..Syntax, ..Checker, ..Scaffold, ..Runner, ..Models, ..HoleMap, ..Progress

export explain, measure, ExplainResult

const TUTOR_ROOT = normpath(joinpath(@__DIR__, ".."))

struct HoleView
    id::String
    file::String
    line::Union{Int,Nothing}
    last_line::Union{Int,Nothing}
    status::String               # "not started" | "implemented"
end

struct ExplainResult
    text::String                                   # deterministic: goldens compare it
    exitcode::Int
    timings::Vector{Pair{String,Float64}}          # wall-clock seconds; never in `text`
    observations::Vector{Progress.Observation}     # for the learner model (src/progress.jl)
end

"""Signature text of each hole's function in the reference: id => (file, signature)."""
function reference_signatures(p::Scaffold.ProjectSpec)
    out = Dict{String,Tuple{String,String}}()
    for h in p.holes
        src = read(joinpath(Scaffold.reference_dir(p), h.file), String)
        tree = JS.parseall(SyntaxNode, src; filename = h.file)
        for l in Scaffold.find_holes(src, h.file)
            l.id == h.id || continue
            for fn in filter(is_long_function, function_nodes(tree))
                nodeline(fn) == l.line && (out[h.id] = (h.file, strip(JS.sourcetext(kids(fn)[1]))))
            end
        end
    end
    return out
end

function locate_holes(p::Scaffold.ProjectSpec, stage::Int, dir::String)
    sigs = reference_signatures(p)
    views = HoleView[]
    for h in p.holes
        h.stage <= stage || continue
        file, sig = sigs[h.id]
        path = joinpath(dir, file)
        line = last_line = nothing
        status = "implemented"
        if isfile(path)
            src = read(path, String)
            tree = try
                JS.parseall(SyntaxNode, src; filename = file)
            catch
                nothing
            end
            if tree !== nothing
                for fn in filter(is_long_function, function_nodes(tree))
                    if strip(JS.sourcetext(kids(fn)[1])) == sig
                        line = nodeline(fn)
                        last_line = JS.source_location(fn.source, JS.last_byte(fn))[1]
                    end
                end
                Scaffold.hole_body_is_todo(src, file, h.id) && (status = "not started")
            end
        end
        push!(views, HoleView(h.id, file, line, last_line, status))
    end
    return views
end

"""Run the project's measure.jl in a fresh process; `nothing` if the project has none."""
function measure(p::Scaffold.ProjectSpec, dir::String; jet::Bool = false, timeout = 600)
    script = joinpath(p.dir, "measure.jl")
    isfile(script) || return nothing
    out = tempname() * ".toml"
    env = Runner.julia_env(; extra_load_path = [TUTOR_ROOT])
    _, timed_out, log = Runner.run_julia_script(script, jet ? [out, "--jet"] : [out]; project = abspath(dir), timeout, env)
    isfile(out) || return Dict{String,Any}("error" => timed_out ? "timed out" :
                                           "measurement process failed: " * first(split(strip(log) * "\n", '\n')))
    d = TOML.parsefile(out)
    rm(out; force = true)
    return d
end

function read_stage(dir::String)
    path = joinpath(dir, ".tutor-project.toml")
    isfile(path) || error("$dir has no .tutor-project.toml; create it with `tutor start <project> <stage> <dir>`")
    d = TOML.parsefile(path)
    return d["project"], d["stage"]
end

function explain(p::Scaffold.ProjectSpec, dir::String; hints::Int = 1, run_measurements::Bool = true,
                 jet::Bool = false)
    _, stage = read_stage(dir)
    io = IOBuffer()
    println(io, "== tutor explain: $(p.name), stage $stage ==")
    timings = Pair{String,Float64}[]
    timed(f, label) = (t0 = time_ns(); r = f(); push!(timings, label => (time_ns() - t0) / 1e9); r)

    rep = timed(() -> Runner.run_tests(dir), "tests (fresh process)")
    findings = timed(() -> Checker.check_paths([joinpath(dir, "src")]; relative_to = dir), "static checker")
    holes = locate_holes(p, stage, dir)
    hm = HoleMap.load_holemap(p)
    deps = Dict{String,Vector{String}}()
    if hm !== nothing
        for (h, ts) in hm["deps"]
            deps[h] = String.(ts)
        end
    end
    meas = run_measurements && isempty(rep.crash) ?
           timed(() -> measure(p, dir; jet), jet ? "measurements incl. JET" : "measurements") : nothing
    base_path = joinpath(p.dir, "measure_baseline.toml")
    baseline = isfile(base_path) ? TOML.parsefile(base_path) : nothing

    # Direct evidence joins the measured map: a testset that raised
    # TODO(hole:h) depends on h even if holemap.toml is missing or stale.
    for t in rep.testsets, h in t.holes
        d = get!(deps, h, String[])
        t.name in d || push!(d, t.name)
    end
    failing = Set(t.name for t in rep.testsets if !Runner.ok(t))
    hole_ids = [h.id for h in holes]
    ranking = Models.rank_by_ochiai(deps, failing, hole_ids)
    todo_seen = Set(h for t in rep.testsets for h in t.holes)

    in_hole(f::Checker.Finding, h::HoleView) = h.line !== nothing && f.file == h.file &&
                                               h.line <= f.line <= h.last_line
    function measured_notes(id)
        notes = String[]
        (meas === nothing || baseline === nothing || !haskey(meas, "inferred")) && return notes
        got = get(meas["inferred"], id, nothing)
        want = get(baseline["inferred"], id, nothing)
        if got !== nothing && want !== nothing && got != want
            push!(notes, got == "Union{}" ?
                  "measured: the compiler infers `Union{}` (this method always throws)" :
                  "measured: return type inferred as `$got`; the reference infers `$want`")
        end
        return notes
    end

    # ---- where to start -------------------------------------------------
    println(io)
    parse_errors = filter(f -> f.rule == "JT000", findings)
    if !isempty(parse_errors)
        f = first(parse_errors)
        println(io, "Start here: $(f.file):$(f.line):$(f.col): the file does not parse ($(f.message)).")
        println(io, "  Nothing else can be checked until it does.")
    elseif !isempty(rep.crash) && isempty(rep.testsets)
        println(io, "Start here: the test run did not get to any testset: $(rep.crash)")
        println(io, "  Usually a load error in src/ (an undefined name, a missing `end`, a method error at top level).")
    elseif isempty(failing)
        println(io, "All $(length(rep.testsets)) testsets pass at stage $stage.")
        next = filter(s -> s > stage, p.stages)
        println(io, isempty(next) ? "  This is the last stage of $(p.name)." :
                                    "  Next: `tutor start $(p.name) $(first(next)) <dir>`.")
    else
        top = ranking[1]
        hv = holes[findfirst(h -> h.id == top[1], holes)]
        if top[2] == 0.0
            println(io, "Start here: failing tests do not depend on any hole of this stage;")
            println(io, "  something outside the holes changed. Compare your src/ with the starter.")
        else
            loc = hv.line === nothing ? hv.file : "$(hv.file):$(hv.line)"
            println(io, "Start here: hole `$(hv.id)` at $loc")
            println(io, "  why: $(top[3]) of the $(length(failing)) failing testsets depend on it " *
                        "(Ochiai $(round(top[2]; digits = 2)))" *
                        (top[4] > 0 ? "; $(top[4]) of its dependent testsets pass" : "") * ".")
            hv.status == "not started" && println(io, "  It still has its TODO body.")
            hv.id in todo_seen && println(io, "  Tests raised TODO(hole:$(hv.id)) from it.")
            for f in findings
                in_hole(f, hv) && println(io, "  finding inside it: $(f.rule) $(f.message) (line $(f.line))")
            end
            foreach(n -> println(io, "  ", n), measured_notes(hv.id))
            spec = p.holes[findfirst(h -> h.id == hv.id, p.holes)]
            println(io, "  Read its docstring: it is the specification. Knowledge component: $(spec.kc).")
        end
    end

    # ---- tests -------------------------------------------------------------
    println(io)
    npass = count(Runner.ok, rep.testsets)
    println(io, "Tests: $npass/$(length(rep.testsets)) testsets pass" *
                (rep.timed_out ? " (TIMED OUT)" : "") *
                (isempty(rep.crash) ? "" : "; crash: $(rep.crash)"))
    for t in rep.testsets
        Runner.ok(t) && continue
        dep_holes = sort!([h for h in hole_ids if t.name in get(deps, h, String[])])
        println(io, "  FAIL $(t.name)  [$(t.failed) failed, $(t.errored) errored; depends on: " *
                    (isempty(dep_holes) ? "no hole" : join(dep_holes, ", ")) * "]")
        for m in t.messages[1:min(end, 2)]
            println(io, "       ", m)
        end
    end

    # ---- holes ---------------------------------------------------------------
    println(io)
    println(io, "Holes at stage $stage (ranked by Ochiai over the measured test-to-hole map):")
    hm === nothing && println(io, "  (no holemap.toml: run `tutor holemap $(p.name)`; ranking unavailable)")
    for (i, (id, score, ef, ep)) in enumerate(ranking)
        hv = holes[findfirst(h -> h.id == id, holes)]
        loc = hv.line === nothing ? hv.file : "$(hv.file):$(hv.line)"
        println(io, "  $i. $(rpad(id, 18)) $(rpad(string(round(score; digits = 2)), 5)) " *
                    "$(rpad(hv.status, 12)) failing-deps=$ef passing-deps=$ep  $loc")
        foreach(n -> println(io, "       ", n), measured_notes(id))
    end

    # ---- static findings --------------------------------------------------------
    println(io)
    println(io, "Static findings ($(length(findings))):")
    isempty(findings) && println(io, "  none")
    for line in split(Checker.format_findings(findings; hints), '\n'; keepempty = false)
        println(io, "  ", line)
    end

    # ---- measurements -----------------------------------------------------------
    println(io)
    println(io, "Measurements (fresh process, 1 thread, after warm-up):")
    if meas === nothing
        println(io, "  skipped" * (isempty(rep.crash) ? "" : " (test run crashed)"))
    elseif haskey(meas, "error")
        println(io, "  unavailable: $(meas["error"])")
    else
        # The bench is built by the student's own code; numbers on a different
        # tree are not comparable with the reference, so say so instead.
        same_bench = baseline !== nothing &&
                     get(meas, "bench_nodecount", nothing) == get(baseline, "bench_nodecount", missing)
        if baseline !== nothing && !same_bench
            println(io, "  the benchmark term differs from the reference's " *
                        "($(get(meas, "bench_nodecount", "not built")) vs $(get(baseline, "bench_nodecount", "?")) nodes): " *
                        "allocations are not compared")
        end
        for key in sort!(collect(keys(get(meas, "allocations", Dict()))))
            got = meas["allocations"][key]
            want = !same_bench ? nothing : get(baseline["allocations"], key, nothing)
            verdict = ""
            if got isa Integer && want isa Integer
                verdict = got > 2 * max(want, 1) ? "  ADVICE: more than 2x the reference ($want)" :
                          "  (reference $want)"
            end
            println(io, "  allocations $key: $got$verdict")
        end
        jet = get(meas, "jet", Dict())
        if haskey(jet, "evaluate_runtime_dispatch_reports")
            println(io, "  JET report_opt(evaluate): $(jet["evaluate_runtime_dispatch_reports"]) runtime-dispatch " *
                        "reports (expected: the tree's children are abstractly typed)")
        else
            println(io, "  JET: $(get(jet, "status", "not run"))" *
                        (startswith(get(jet, "status", ""), "not run") ? "; it adds about a minute" : ""))
        end
    end

    # ---- learner-model observations (the caller applies them to the state) -----
    observations = Progress.Observation[]
    if isempty(parse_errors) && isempty(rep.crash)
        excused = Set(t.name for t in rep.testsets
                      if !Runner.ok(t) && t.failed == 0 && t.errored == t.todo_errors)
        for hv in holes
            (hv.status == "implemented" && hv.line !== nothing) || continue
            verdict = Progress.observe(hv.id, deps, failing, hole_ids; excused)
            verdict in (:correct, :incorrect) || continue
            src = join(readlines(joinpath(dir, hv.file))[hv.line:hv.last_line], '\n')
            spec = p.holes[findfirst(h -> h.id == hv.id, p.holes)]
            push!(observations, Progress.Observation(p.name, hv.id, spec.kc, verdict === :correct,
                                                     Progress.attempt_hash(src)))
        end
    end

    code = (isempty(failing) && isempty(rep.crash) && Checker.exit_code(findings) == 0) ? 0 : 1
    return ExplainResult(String(take!(io)), code, timings, observations)
end

end # module Explain
