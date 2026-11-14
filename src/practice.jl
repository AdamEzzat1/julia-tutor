# Running and grading learner code for the course (CLI and the local server).
#
# * `run_code`: the sandbox's "Run" button, and how example outputs are recorded.
# * `grade`: a practice submission -> correctness against the reference, then
#   speed, memory, growth and type stability *relative to the reference*,
#   measured in the same process (src/child/sandbox.jl). `assess` turns the raw
#   measurements into verdicts and feedback; it is a pure function, tested on
#   synthetic measurements, and the website shows its output verbatim, so the
#   CLI and the browser always say the same thing.
# * `verify_unit` / `record_unit`: example outputs and the grader's own tests
#   (each problem's variants must get the verdicts they declare).
#
# Where the child runs is `Runner.SANDBOX[]`: a plain process (the CLI, for
# code the learner typed) or the sandbox container (`tutor serve`, by default).

module Practice

using TOML
using ..Runner, ..Course, ..Checker

export run_code, grade, assess, format_grade, record_unit, verify_unit, RunResult

const CHILD = joinpath(@__DIR__, "child", "sandbox.jl")
const MAX_OUTPUT = 100_000
const SEED = 20261108

# Verdict thresholds (time ratio = learner / reference at the largest size).
const FAST = 0.75          # at most this: faster than the reference
const PAR = 1.75           # at most this: on par (same process, interleaved samples)
const SLOWER = 5.0         # above this: slow
const ALLOC_SLACK = 256    # bytes of extra allocation tolerated (a boxed value or two)
const GROWTH_GAP = 0.5     # exponent difference that counts as worse growth

"""An image the code produced: a figure it returned, or a PNG/SVG it saved."""
struct Image
    name::String
    mime::String
    data::Vector{UInt8}
end

struct RunResult
    output::String
    ok::Bool
    timed_out::Bool
    seconds::Float64
    images::Vector{Image}
end
RunResult(output, ok, timed_out, seconds) = RunResult(output, ok, timed_out, seconds, Image[])

const IMAGE_MIMES = Dict(".png" => "image/png", ".svg" => "image/svg+xml")
const MAX_IMAGES = 4
const MAX_IMAGE_BYTES = 3_000_000

"""
PNG and SVG files the code left in `dir` (sorted by name, at most
`MAX_IMAGES`, each at most `MAX_IMAGE_BYTES`; anything else is ignored).
"""
function collect_images(dir::String)
    imgs = Image[]
    for f in sort!(readdir(dir))
        mime = get(IMAGE_MIMES, lowercase(splitext(f)[2]), nothing)
        (mime === nothing || !isfile(joinpath(dir, f))) && continue
        filesize(joinpath(dir, f)) <= MAX_IMAGE_BYTES || continue
        push!(imgs, Image(f, mime, read(joinpath(dir, f))))
        length(imgs) == MAX_IMAGES && break
    end
    return imgs
end

"""
Replace the machine-specific standard-library path in output (method lists in
a MethodError print file paths) with `<stdlib>`, so recorded outputs agree
between Windows and Linux.
"""
function scrub(s::AbstractString)
    for root in unique([Sys.STDLIB, replace(Sys.STDLIB, '\\' => '/'), CONTAINER_STDLIB])
        s = replace(s, Regex("\\Q" * root * "\\E[\\\\/][^\\s:]*") =>
                       m -> "<stdlib>/" * replace(m[ncodeunits(root)+2:end], '\\' => '/'))
    end
    # Counters that change whenever the sandbox child gains a function: the
    # number of an anonymous function in a frame (`#28`), and world ages.
    s = replace(s, r"(?<=  @ )#\d+(?= at line)" => "anonymous function")
    s = replace(s, r"world age (\d+), while current world is (\d+)" =>
                   m -> (w = parse.(Int, match(r"(\d+)\D+(\d+)", m).captures);
                         w[2] == w[1] + 1 ? "world age W, while current world is W+1" : m))
    return s
end

function clip(s::AbstractString, n = MAX_OUTPUT)
    s = scrub(replace(s, "\r\n" => "\n"))
    ncodeunits(s) <= n ? s : s[1:prevind(s, n)] * "\n… output truncated at $(n ÷ 1000) kB"
end

# The container's standard library, for `scrub` (a MethodError lists file paths).
const CONTAINER_STDLIB = "/usr/local/julia/share/julia/stdlib/v1.10"

"""
Start the sandbox child (src/child/sandbox.jl) on files in `dir`: a plain
process, or with `Runner.SANDBOX[] === :docker` in a fresh container that gets
copies of the files (nothing of the host is mounted) and hands back the files
the child wrote, which land in `dir` as if it had run here.
"""
function child(args::Vector{String}, dir::String; env::AbstractString, timeout::Real, threads::Int = 1)
    if Runner.SANDBOX[] === :docker
        files = Dict{String,String}(basename(a) => read(a, String) for a in args if isfile(a))  # code and jobs: text
        cargs = [startswith(a, dir) ? basename(a) : a for a in args]
        rc, to, log, out = Runner.run_contained(files, cargs; project_env = String(env), timeout, threads)
        for (name, content) in out
            name == basename(name) && write(joinpath(dir, name), content)
        end
        return rc, to, log
    end
    return Runner.run_julia_script(CHILD, args; project = Course.env_dir(env), timeout, check_bounds = false,
                                   threads, dir)
end

"""
Seconds a Run may take in `env`: loading a large package (Makie, Turing,
DifferentialEquations) and compiling its first call takes far longer than
anything in the standard library.
"""
run_timeout(env::AbstractString) = env == "base" ? 60 : 180

"""A contained run the kernel stopped for using more than its memory limit."""
out_of_memory(rc, timed_out) = Runner.SANDBOX[] === :docker && !timed_out && rc == Runner.OOM_EXIT
oom_message(env) = "the run used more than the sandbox's $(Runner.image_memory(Runner.env_image(env))) of memory and was stopped"

"""Run `code` in a fresh process in the unit environment `env` (REPL-like display)."""
function run_code(code::AbstractString; env::AbstractString = "base", mode::AbstractString = "repl",
                  timeout::Real = 60)
    dir = mktempdir()
    path = joinpath(dir, "main.jl")
    write(path, code)
    t = time()
    rc, to, log = child(["run", path, String(mode)], dir; env, timeout)
    images = collect_images(dir)
    try rm(dir; recursive = true, force = true) catch end
    out = clip(log)
    out_of_memory(rc, to) &&
        (out *= (isempty(out) || endswith(out, "\n") ? "" : "\n") * "ERROR: " * oom_message(env) * "\n")
    to && (out *= (isempty(out) || endswith(out, "\n") ? "" : "\n") *
                  "ERROR: timed out after $(timeout) s (an infinite loop, or a very slow computation)\n")
    return RunResult(out, rc == 0 && !to, to, time() - t, images)
end

# ---- grading -------------------------------------------------------------------------

"""Packages of a unit environment (its Project.toml `[deps]`), sorted."""
function env_deps(env)
    f = joinpath(Course.env_dir(env), "Project.toml")
    isfile(f) || return String[]
    return sort!(collect(keys(get(TOML.parsefile(f), "deps", Dict()))))
end

function job_dict(p::Course.Problem, code::AbstractString; env::AbstractString = "base")
    Dict("using" => isempty(p.packages) ? env_deps(env) : sort(p.packages), "entry" => p.entry, "reference" => p.reference, "submission" => String(code),
         "cases" => p.cases, "gen" => p.gen, "compare" => p.compare, "checker" => p.checker, "rtol" => p.rtol,
         "check_type" => p.check_type, "compare_args" => p.compare_args, "seed" => SEED,
         "perf_args" => p.perf === nothing ? "" : p.perf.args,
         "sizes" => p.perf === nothing ? Int[] : p.perf.sizes,
         "mutates" => p.perf === nothing ? false : p.perf.mutates, "repeats" => p.repeats)
end

function static_findings(code)
    fs = try
        Checker.check_source(code, "main.jl")
    catch
        Checker.Finding[]
    end
    return Any[Dict("rule" => f.rule, "severity" => string(f.severity), "line" => f.line, "message" => f.message)
               for f in fs]
end

"""Grade a submission for problem `p`. Returns a JSON-ready Dict (see `assess`)."""
function grade(p::Course.Problem, code::AbstractString; env::AbstractString = "base", timeout::Real = 120)
    dir = mktempdir()
    jobpath = joinpath(dir, "job.toml"); outpath = joinpath(dir, "result.toml")
    open(io -> TOML.print(io, job_dict(p, code; env)), jobpath, "w")
    t = time()
    rc, to, log = child(["grade", jobpath, outpath], dir; env, timeout, threads = p.threads)
    raw = isfile(outpath) ? TOML.tryparsefile(outpath) : nothing
    raw isa Dict && haskey(raw, "status") || (raw = nothing)   # unreadable or partial: a crash
    rm(dir; recursive = true, force = true)
    log = out_of_memory(rc, to) ? oom_message(env) * "\n" * log : log
    r = assess(p, raw; timed_out = to, log = clip(log, 4000), findings = static_findings(code))
    r["seconds"] = round(time() - t; digits = 1)
    return r
end

item(level, title, detail = "") = Dict("level" => level, "title" => title, "detail" => detail)

function fmt_ns(ns)
    ns < 1e3 && return string(round(ns; digits = 1), " ns")
    ns < 1e6 && return string(round(ns / 1e3; digits = 1), " μs")
    ns < 1e9 && return string(round(ns / 1e6; digits = 1), " ms")
    return string(round(ns / 1e9; digits = 2), " s")
end
function fmt_bytes(b)
    b < 1024 && return "$(Int(b)) B"
    b < 1024^2 && return string(round(b / 1024; digits = 1), " KiB")
    return string(round(b / 1024^2; digits = 1), " MiB")
end
fmt_ratio(r) = r >= 1000 ? "over 1000×" : r >= 10 ? string(round(Int, r), "×") : string(round(r; digits = 1), "×")

growth(s1, s2, k) = log(s2[k] / s1[k]) / log(s2["n"] / s1["n"])

# "`acc::Any`", or "`acc::Any` in `helper`" when the local is not in the entry.
where(l, entry) = (f = get(l, "function", entry); f == entry ? "" : " in `$f`")
local_label(l, entry) = "`$(l["name"])::$(l["type"])`" * where(l, entry)

function type_hint(l, entry = "")
    t = l["type"]
    w = where(l, entry)
    if get(l, "kind", "") == "abstract-container"
        return "`$(l["name"])`$w is a `$t`: its elements have an abstract type, so each one is boxed and every " *
               "use is a dynamic lookup. Give the container a concrete element type (`Float64[]`, `zeros(n)`, `Ref(0.0)`)."
    elseif occursin(r"^Union\{(Float64|Int64|Float32|Int32|Rational\{Int64\}|BigInt|BigFloat)(, (Float64|Int64|Float32|Int32|Rational\{Int64\}|BigInt|BigFloat))+\}$", t)
        return "`$(l["name"])`$w starts as one number type and becomes another. Initialise it with the " *
               "type it will end up as, e.g. `zero(eltype(v))` instead of `0`."
    elseif occursin("Nothing", t)
        return "`$(l["name"])`$w is sometimes `nothing`. That is fine for a search result you check right away; " *
               "otherwise give it a value of the final type up front."
    end
    return nothing   # generic: merged into one sentence by the caller
end

"""
    assess(p, raw; timed_out, log, findings) -> Dict

Pure function from the child's raw result to verdicts and feedback. Keys:
`status` (passed, failed, load-error, no-entry, timeout, crash, internal-error),
`correctness`, `performance` (or nothing), `feedback` (ordered items with
`level` pass/warn/fail/info), `findings` (static checker), `verdicts` (the
canonical labels that problem variants are checked against).
"""
function assess(p::Course.Problem, raw; timed_out::Bool = false, log::AbstractString = "", findings = Any[])
    out = Dict{String,Any}("problem" => p.id, "correctness" => nothing, "performance" => nothing,
                           "findings" => findings, "feedback" => Any[], "verdicts" => String[])
    fb = out["feedback"]; v = out["verdicts"]
    if raw === nothing
        out["status"] = timed_out ? "timeout" : "crash"
        push!(fb, timed_out ? item("fail", "Timed out before your code finished loading") :
                              item("fail", "The grading process crashed", strip(log)))
        push!(v, "incorrect")
        return out
    end
    st = raw["status"]
    if st == "reference-error"
        out["status"] = "internal-error"
        push!(fb, item("fail", "The problem's reference solution failed to load (a bug in the course, not your code)", raw["message"]))
        return out
    elseif st in ("load-error", "no-entry")
        out["status"] = st
        push!(fb, item("fail", st == "load-error" ? "Your code does not run" : "Missing function", raw["message"]))
        push!(v, "load-error", "incorrect")
        return out
    end
    c = get(raw, "correctness", nothing)
    if c === nothing
        out["status"] = timed_out ? "timeout" : "crash"
        push!(fb, item("fail", timed_out ? "Timed out while running the tests (an infinite loop?)" : "The grading process crashed",
                       timed_out ? "" : strip(log)))
        push!(v, "incorrect")
        return out
    end
    out["correctness"] = c
    if c["passed"] < c["total"]
        out["status"] = timed_out ? "timeout" : "failed"
        nfail = c["total"] - c["passed"]
        f = first(c["failures"])
        detail = "$(f["input"])\n  expected: $(f["expected"])\n  got:      $(f["got"])"
        if p.repeats > 1
            detail *= "\n\nEach case runs $(p.repeats) times on $(p.threads) thread$(p.threads == 1 ? "" : "s"). " *
                      "A total that is wrong only on some runs, or differs from run to run, is a data race: tasks " *
                      "updating shared state (`total[] += x`) lose each other's updates. Give each task its own " *
                      "partial result and combine them with `fetch`."
        end
        push!(fb, item("fail", "$nfail of $(c["total"]) test cases fail ($(f["reason"]) first)", detail))
        push!(v, "incorrect")
        return out
    end
    out["status"] = "passed"
    push!(v, "correct")
    how = p.compare == "isapprox" ? "within a relative tolerance of $(p.rtol)" : "exactly (`isequal`)"
    typ = p.check_type ? ", and with the same result type" : ""
    push!(fb, item("pass", "Correct on all $(c["total"]) cases",
                   "$(c["explicit"]) shown and $(c["total"] - c["explicit"]) seeded random cases, compared with the reference $how$typ."))
    pr = get(raw, "perf", nothing)
    if pr === nothing
        p.perf === nothing && return out
        if haskey(raw, "perf_error")
            # The measurement itself failed: a property of the run, not a speed verdict.
            push!(fb, item("warn", "Performance could not be measured",
                           "Your function is correct on the tests, but calling it on the larger performance inputs " *
                           "(n = $(join(p.perf.sizes, " and n = "))) failed:
" * raw["perf_error"]))
            out["performance"] = Dict("overall" => "needs-work", "timed_out" => false, "error" => raw["perf_error"])
            return out
        end
        push!(fb, item("fail", "Performance measurement timed out",
                       "Your function is correct but far slower than the reference at n = $(join(p.perf.sizes, " and n = ")). " *
                       "Look for work repeated inside a loop."))
        push!(v, "slow")
        out["performance"] = Dict("overall" => "needs-work", "timed_out" => true)
        return out
    end

    s1, s2 = pr["sizes"][1], pr["sizes"][end]
    ratio = s2["sub_ns"] / s2["ref_ns"]
    tv = ratio <= FAST ? "fast" : ratio <= PAR ? "par" : ratio <= SLOWER ? "slower" : "slow"
    tv in ("fast", "par") && push!(v, "fast")
    tv == "slow" && push!(v, "slow")
    extra = s2["sub_bytes"] - s2["ref_bytes"]
    mv = extra > max(ALLOC_SLACK, s2["ref_bytes"] ÷ 2) ? "allocates" : "ok"
    mv == "allocates" && push!(v, "allocates")
    es = growth(s1, s2, "sub_ns"); er = growth(s1, s2, "ref_ns")
    gv = (es - er > GROWTH_GAP && ratio > 2) ? "worse" : "ok"
    gv == "worse" && push!(v, "scaling")
    # Relative to the reference: a local whose abstract type the reference's
    # entry function also has (a `Vector{Any}` from `ex.args`, a package's
    # untyped internals) is how the problem is, not the learner's doing.
    ref_abstract = Set(l["type"] for l in get(pr, "ref_locals", Any[]) if l["kind"] in ("abstract", "abstract-container"))
    abstract_locals = filter(l -> l["kind"] in ("abstract", "abstract-container") && !(l["type"] in ref_abstract), pr["locals"])
    union_locals = filter(l -> l["kind"] == "small-union", pr["locals"])
    ret_bad = (pr["return_sub_kind"] == "abstract" && pr["return_ref_kind"] != "abstract") ||
              (pr["return_sub_kind"] == "small-union" && pr["return_ref_kind"] == "concrete")
    sv = (ret_bad || !isempty(abstract_locals)) ? "unstable" : "stable"
    sv == "unstable" && push!(v, "unstable")
    flags = count(==(true), (tv in ("slower", "slow"), mv == "allocates", gv == "worse", sv == "unstable"))
    overall = flags == 0 ? "excellent" : (flags == 1 && tv != "slow") ? "good" : "needs-work"

    n = s2["n"]
    tline = "$(fmt_ns(s2["sub_ns"])) per call at n = $n; the reference takes $(fmt_ns(s2["ref_ns"])) ($(fmt_ratio(ratio)) its time)."
    if tv == "fast"
        push!(fb, item("pass", "Speed: faster than the reference", tline))
    elseif tv == "par"
        push!(fb, item("pass", "Speed: on par with the reference", tline))
    else
        why = (mv == "ok" && sv == "stable" && gv == "ok") ?
              " Same allocations and types as the reference, so the gap is in the work per element: look for repeated work in the loop body." : ""
        push!(fb, item(tv == "slow" ? "fail" : "warn", "Speed: $(fmt_ratio(ratio)) slower than the reference", tline * why))
    end
    if mv == "ok"
        push!(fb, item("pass", s2["sub_bytes"] == 0 ? "Memory: no allocations" : "Memory: allocates no more than the reference",
                       "$(fmt_bytes(s2["sub_bytes"])) per call at n = $n; the reference allocates $(fmt_bytes(s2["ref_bytes"]))."))
    else
        push!(fb, item("warn", "Memory: allocates $(fmt_bytes(s2["sub_bytes"])) per call at n = $n",
                       "The reference allocates $(fmt_bytes(s2["ref_bytes"])). Usual causes: slicing (`x[a:b]` copies; `@view` does not), " *
                       "building an intermediate array where a loop or a generator would do (`sum(f(x) for x in v)`), " *
                       "or broadcasting into a new array instead of an existing one (`out .= ...`)."))
    end
    if gv == "worse"
        push!(fb, item("warn", "Growth: about n^$(round(es; digits = 1)), the reference about n^$(round(er; digits = 1))",
                       "Measured at n = $(s1["n"]) and n = $n. A higher exponent usually means a nested loop or a linear search inside a loop " *
                       "(`x in v` on a Vector, `findfirst`); a `Set` or `Dict` lookup takes constant time."))
    end
    if sv == "stable"
        unions = isempty(union_locals) ? "" :
            " Small unions the compiler splits efficiently: " * join([local_label(l, p.entry) for l in union_locals], ", ") * "."
        push!(fb, item("pass", "Types: inferred concretely", "Returns `$(pr["return_sub"])`; every local variable has a concrete type, " *
                       "in `$(p.entry)` and in the functions it calls that you defined." * unions))
    else
        parts = String[]
        ret_bad && push!(parts, "returns `$(pr["return_sub"])` where the reference returns `$(pr["return_ref"])` " *
                                "(different branches return different types, e.g. `0` in one and `0.0` in another).")
        generic = String[]
        for l in abstract_locals
            h = type_hint(l, p.entry)
            h === nothing ? push!(generic, "`$(l["name"])`" * where(l, p.entry)) : push!(parts, h)
        end
        isempty(generic) || push!(parts, "The compiler cannot pin down the type of " * join(generic, ", ", " and ") *
            ". Usual causes: a non-`const` global, an `Any[]` or untyped container, a struct field with an abstract type, " *
            "or a variable reassigned to a different type.")
        push!(fb, item("warn", "Types: not type-stable" * (isempty(abstract_locals) ? "" : " (" * join([local_label(l, p.entry) for l in abstract_locals], ", ") * ")"),
                       join(parts, " ")))
    end
    out["performance"] = Dict("overall" => overall, "time" => tv, "ratio" => ratio, "memory" => mv,
                              "growth" => gv, "growth_sub" => es, "growth_ref" => er, "types" => sv,
                              "return_sub" => pr["return_sub"], "return_ref" => pr["return_ref"],
                              "locals" => pr["locals"], "sizes" => pr["sizes"], "timed_out" => false)
    return out
end

"""Plain-text rendering of a grade result for the terminal."""
function format_grade(r)
    io = IOBuffer()
    mark = Dict("pass" => "✓", "warn" => "!", "fail" => "✗", "info" => "·")
    println(io, "Result: ", r["status"],
            r["performance"] isa AbstractDict ? "  ·  performance: " * r["performance"]["overall"] : "")
    for f in r["feedback"]
        println(io, mark[f["level"]], " ", f["title"])
        isempty(f["detail"]) || println(io, "    ", replace(f["detail"], "\n" => "\n    "))
    end
    for f in r["findings"]
        println(io, "· checker ", f["rule"], " line ", f["line"], ": ", f["message"])
    end
    return String(take!(io))
end

# ---- course outputs ------------------------------------------------------------------------

"""Output of the reference on each explicit case, as the REPL would display it."""
function samples(p::Course.Problem, env)
    calls = join(["println(\"<<<case>>>\"); try show(stdout, MIME\"text/plain\"(), $(p.entry)($a)) catch e; print(\"throws \", typeof(e)) end; println()"
                  for a in p.cases], "\n")
    # Cases see what the grader's Cases module loads (Random and the problem's
    # packages, else the env's), not only what the reference happens to load.
    usings = join(["using " * x for x in ["Random"; isempty(p.packages) ? env_deps(env) : p.packages]], "\n")
    r = run_code(usings * "\n" * p.reference * "\n" * calls * "\nnothing"; env, mode = "file", timeout = 120)
    r.ok || error("reference for $(p.id) failed:\n$(r.output)")
    parts = split(r.output, "<<<case>>>\n")[2:end]
    length(parts) == length(p.cases) || error("$(p.id): sample output has $(length(parts)) parts for $(length(p.cases)) cases")
    return Any[Dict("call" => "$(p.entry)($a)", "result" => rstrip(s)) for (a, s) in zip(p.cases, parts)]
end

# Examples recorded at once. Containers may use up to Runner.CONTAINER_MEMORY
# each and Docker Desktop's VM has a fixed total (8 GB here); examples peak
# well under half of it, so two at a time; plain processes share the host.
# TUTOR_NTASKS overrides it (for example when several recordings share a host).
default_ntasks() = haskey(ENV, "TUTOR_NTASKS") ? max(1, parse(Int, ENV["TUTOR_NTASKS"])) :
                   Runner.SANDBOX[] === :docker ? 2 : 4

"""
Record every example output and problem sample of a unit (runs Julia). Code
of `output` questions is recorded like an example. Figures are listed by file
name (`<key>-figure.png`); with `figures = dir` their bytes are written there
(the directory is emptied first). Image bytes are never compared: renderers
differ between machines, so `verify` checks only which figures exist.
"""
function record_unit(u::Course.Unit; ntasks::Int = default_ntasks(), figures::Union{Nothing,String} = nothing)
    examples = unique(Course.recorded_code(u))
    results = asyncmap(((c, m),) -> run_code(c; env = u.env, mode = m, timeout = 240), examples; ntasks)
    ex = Dict{String,Any}()
    figures === nothing || rm(figures; recursive = true, force = true)
    for ((c, m), r) in zip(examples, results)
        r.timed_out && error("$(u.id): an example timed out:\n$c")
        k = Course.example_key(c, m)
        ex[k] = Dict{String,Any}("output" => r.output, "ok" => r.ok)
        isempty(r.images) && continue
        ex[k]["images"] = [k * "-" * i.name for i in r.images]
        figures === nothing && continue
        mkpath(figures)
        foreach(i -> write(joinpath(figures, k * "-" * i.name), i.data), r.images)
    end
    sm = Dict{String,Any}(p.id => samples(p, u.env) for p in u.problems)
    return Dict("verified_on" => string(VERSION), "examples" => ex, "samples" => sm)
end

function outputs_text(d)
    io = IOBuffer()
    println(io, "# Generated by `tutor course record`: example outputs and problem samples, run on Julia $(d["verified_on"]). Do not edit.")
    TOML.print(io, d; sorted = true)
    return String(take!(io))
end

"""
Output as `verify` compares it. A MethodError's "Closest candidates are:" list
is ranked from every method loaded at the time, so a rebuilt image (or one
more stdlib loaded) reorders it while the error itself is the same; the list
is dropped for the comparison and kept in the recording that learners see.
"""
comparable(s::AbstractString) =
    replace(rstrip(s), r"(?m)^Closest candidates are:\n(?:  .*\n?)*" => "Closest candidates are: …\n")

same_example(a, b) = keys(a) == keys(b) &&
    all(k -> k == "output" ? comparable(a[k]) == comparable(b[k]) : a[k] == b[k], keys(a))

# Relative tolerance for numbers in problem samples. The last digits of a
# Float32 training loop or an HMC chain move between CPUs (FMA and SIMD paths
# in the BLAS and in LLVM's code), which is not a change in the course.
const SAMPLE_RTOL = 1e-4
const NUMBER = r"[-+]?(?:\d+\.?\d*|\.\d+)(?:[eEf][-+]?\d+)?"

"""Two sample results agree: the same text around the numbers, numbers within `SAMPLE_RTOL`."""
function same_sample(a::AbstractString, b::AbstractString)
    a == b && return true
    split(a, NUMBER) == split(b, NUMBER) || return false
    na = [parse(Float64, replace(m.match, 'f' => 'e')) for m in eachmatch(NUMBER, a)]
    nb = [parse(Float64, replace(m.match, 'f' => 'e')) for m in eachmatch(NUMBER, b)]
    return length(na) == length(nb) && all(isapprox(x, y; rtol = SAMPLE_RTOL, atol = 1e-8) for (x, y) in zip(na, nb))
end

"""Problems with the recorded samples of a unit, each with the old and new result."""
function sample_problems(uid, stored, now)
    stored === nothing && return ["$uid: no recorded problem samples (re-record)"]
    out = String[]
    keys(stored) == keys(now) || push!(out, "$uid: problems with samples differ (re-record)")
    for (pid, cases) in now
        old = get(stored, pid, nothing)
        old === nothing && continue
        length(old) == length(cases) || (push!(out, "$uid: $pid has a different number of samples (re-record)"); continue)
        for (o, c) in zip(old, cases)
            o["call"] == c["call"] && same_sample(o["result"], c["result"]) && continue
            push!(out, "$uid: sample $pid changed (re-record and review)\n--- call\n$(c["call"])\n--- recorded\n$(o["result"])\n--- now\n$(c["result"])")
        end
    end
    return out
end

"""
The key of an `output` question is the code's measured output: the right
choice must equal it (trailing whitespace aside) and no other choice may.
"""
function question_key_problems(u::Course.Unit, rec)
    out = String[]
    for (i, q) in enumerate(Course.questions(u))
        q.kind == "output" || continue
        r = get(rec["examples"], Course.example_key(q.code, "repl"), nothing)
        r === nothing && (push!(out, "$(u.id) question $i: its code was not run"); continue)
        got = rstrip(r["output"])
        comparable(q.choices[q.answer]) == comparable(got) ||
            push!(out, "$(u.id) question $i: the answer is not the code's output\n--- answer\n$(q.choices[q.answer])\n--- output\n$got")
        # (no matching choice at all is the message above: the answer is not the output)
        count(c -> comparable(c) == comparable(got), q.choices) > 1 &&
            push!(out, "$(u.id) question $i: more than one choice equals the output")
    end
    return out
end

"""
Run each break-it probe at both ends of its edge, as the site runs it at a
learner's value, and check it agrees with the sweep (`Course.probe_problems`).
A sweep without a single edge is reported by `breakit_key_problems`; its probe
is not run.
"""
function breakit_probe_problems(u::Course.Unit, rec; log = stdout)
    out = String[]
    exs = get(rec, "examples", Dict())
    for s in u.sections, e in s.examples
        b = e.breakit
        b === nothing && continue
        r = get(exs, Course.example_key(e.code, e.mode), nothing)
        sc = r === nothing ? nothing : Course.score_breakit(b, r["output"])
        sc isa NamedTuple || continue
        lo, hi = (run_code(Course.probe_code(b, x); env = u.env, timeout = 120).output for x in b.edge)
        println(log, "  break-it probe '", s.title, "' at ", b.edge[1], " and ", b.edge[2])
        append!(out, ["$(u.id) '$(s.title)' break-it probe: $m" for m in Course.probe_problems(b, sc.side, lo, hi)])
    end
    return out
end

"""
Run the convergence tests of a find-the-bug problem on `code`, each in a fresh
process, as the site runs them through `tutor serve`. One entry per test:
`(name, value, passed, output)`; `value` is `nothing` when the run printed no
reading (an error, a crash), which counts as a fail.
"""
function run_bug_tests(p::Course.Problem, code::AbstractString; env::AbstractString = "base", timeout::Real = 120)
    b = p.bug
    out = NamedTuple{(:name, :value, :passed, :output),Tuple{String,Union{Nothing,Float64},Bool,String}}[]
    for t in b.tests
        r = run_code(Course.bug_test_code(code, t); env, timeout)
        v = Course.bug_test_value(t, r.output)
        push!(out, (name = t.name, value = v, passed = Course.bug_test_passes(t, v), output = r.output))
    end
    return out
end

"""Plain-text table of convergence-test results, with each failing test's explanation."""
function format_bug_tests(p::Course.Problem, results)
    io = IOBuffer()
    println(io, "Convergence tests:")
    for (t, r) in zip(p.bug.tests, results)
        got = r.value === nothing ? "no reading" : string(r.value)
        println(io, r.passed ? "✓ " : "✗ ", t.name, ": measured ", got, ", expected ", t.expect[1], " to ", t.expect[2])
        r.passed || println(io, "    ", replace(strip(t.explain), "\n" => "\n    "))
    end
    return String(take!(io))
end

"""
The measured checks of each find-the-bug problem: every convergence test
passes on the reference, and at least one fails on the planted starter (the
tests can see the planted error).
"""
function bug_problems(u::Course.Unit; log = stdout)
    out = String[]
    for p in u.problems
        p.bug === nothing && continue
        isempty(Course.bug_problems(p, u.kcs)) || continue   # structural problems are reported by validate
        ref = run_bug_tests(p, p.reference; env = u.env)
        bad = run_bug_tests(p, p.starter; env = u.env)
        for (t, r, s) in zip(p.bug.tests, ref, bad)
            println(log, "  ", rpad(p.id * " test '" * t.name * "'", 70), "  reference ", something(r.value, "none"),
                    "  planted ", something(s.value, "none"))
            r.passed || push!(out, "$(p.id): convergence test '$(t.name)' fails on the reference " *
                                   "(measured $(something(r.value, "no reading")), expected $(t.expect[1]) to $(t.expect[2]))" *
                                   (r.value === nothing ? ":\n" * r.output : ""))
        end
        all(s -> s.passed, bad) && push!(out, "$(p.id): every convergence test passes on the planted starter (the tests cannot see the bug)")
    end
    return out
end

# Verdicts that come from timing (allocations and type stability are counted,
# not timed, so they are deterministic and never re-measured).
const PERF_VERDICTS = ("slow", "fast", "scaling")
const PERF_RETRIES = 2

"""
Check a unit against its recorded outputs and run the grader's own tests.
Returns a list of problems (empty = verified).
"""
function verify_unit(u::Course.Unit; grade_variants::Bool = true, ntasks::Int = default_ntasks(), log = stdout)
    problems = String[]
    u.status == "planned" && return problems
    path = Course.outputs_path(u)
    isfile(path) || return ["$(u.id): no recorded outputs (run `tutor course record $(u.id)`)"]
    rec = record_unit(u; ntasks)
    if outputs_text(rec) != read(path, String)
        stored = Course.load_outputs(u)
        for (k, v) in rec["examples"]
            old = get(get(stored, "examples", Dict()), k, nothing)
            checkable = any(e -> Course.example_key(e.code, e.mode) == k && e.check, (e for s in u.sections for e in s.examples)) ||
                        any(q -> q.kind == "output" && Course.example_key(q.code, "repl") == k, Course.questions(u))
            if old === nothing
                push!(problems, "$(u.id): example $k has no recorded output")
            elseif checkable && !same_example(old, v)
                push!(problems, "$(u.id): example $k output changed:\n--- recorded\n$(old["output"])\n--- now\n$(v["output"])")
            end
        end
        append!(problems, sample_problems(u.id, get(stored, "samples", nothing), rec["samples"]))
        length(get(stored, "examples", Dict())) == length(rec["examples"]) ||
            push!(problems, "$(u.id): recorded outputs have stale entries (re-record)")
        get(stored, "verified_on", "") == string(VERSION) || push!(problems, "$(u.id): outputs were recorded on another Julia")
    end
    append!(problems, question_key_problems(u, rec))
    append!(problems, Course.prediction_key_problems(u, rec))
    append!(problems, Course.checkpoint_key_problems(u, rec))   # on the fresh run: checked even for check = false
    append!(problems, Course.breakit_key_problems(u, rec))
    append!(problems, breakit_probe_problems(u, rec; log))
    grade_variants || return problems
    append!(problems, bug_problems(u; log))
    for p in u.problems
        # "fast" only exists when there is a performance section to measure.
        ref_expect = p.perf === nothing ? ["correct"] : ["correct", "fast"]
        jobs = Tuple{String,String,Vector{String}}[("reference", p.reference, ref_expect),
                                                   ("starter", p.starter, String[])]
        append!(jobs, [(v.label, v.code, v.expect) for v in p.variants])
        # Sequential: performance verdicts are measured, and parallel runs would
        # compete for the CPU. Each run is still self-relative (learner vs reference).
        for (label, code, expect) in jobs
            r = grade(p, code; env = u.env)
            println(log, "  ", rpad(p.id * "/" * label, 46), "  ", r["status"], "  ", join(r["verdicts"], ","))
            # Speed verdicts are measurements; on a shared machine one can miss
            # its threshold by noise. Re-measure up to PERF_RETRIES times before
            # reporting; correctness verdicts are never retried.
            for attempt in 1:PERF_RETRIES
                missing_perf = [x for x in expect if x in PERF_VERDICTS && !(x in r["verdicts"])]
                isempty(missing_perf) && break
                "correct" in r["verdicts"] || break   # wrong or crashed: nothing was timed
                r = grade(p, code; env = u.env)
                println(log, "  ", rpad(p.id * "/" * label, 46), "  ", r["status"], "  ", join(r["verdicts"], ","),
                        "  (re-measured: '", join(missing_perf, "', '"), "' was missing)")
            end
            label == "starter" && r["status"] == "passed" &&
                push!(problems, "$(p.id): the starter already passes (the problem is trivial)")
            r["status"] == "internal-error" && push!(problems, "$(p.id): $(r["feedback"][1]["detail"])")
            for x in expect
                x in r["verdicts"] || push!(problems, "$(p.id)/$label: expected verdict '$x', got [$(join(r["verdicts"], ", "))]")
            end
        end
    end
    return problems
end

end # module Practice
