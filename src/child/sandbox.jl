# Child process for the course sandbox. Always started fresh by the parent
# (src/practice.jl via Runner.run_julia_script), in the unit's environment.
#
#   julia sandbox.jl run <code.jl> <repl|file>
#       Evaluate the code in Main like the REPL does: `repl` uses REPL soft scope
#       (top-level loops can assign globals), `file` is plain `include`
#       semantics. The value of the last expression is displayed unless the
#       code ends with `;`. Errors print as "ERROR: ..." plus the frames that
#       are in the learner's code. Exit 0 on success, 1 on an error.
#
#   julia sandbox.jl grade <job.toml> <result.toml>
#       Load the reference and the submission into separate modules, compare
#       them on explicit and seeded random cases, then (if all are correct)
#       measure time, allocations and inferred types of both, at two sizes.
#       The result file is written after each phase, so a timeout during the
#       performance phase still reports correctness.
#
# Containment comes from where the parent starts this process (src/runner.jl):
# a container without network and with a read-only file system under
# `tutor serve --sandbox=docker`, or a plain process otherwise.
#
# Everything here lives in the module `TutorChild`, so the learner's code (which
# runs in Main) sees an empty Main, as in a fresh REPL. Helpers defined in Main
# would shadow package exports: Main's own `sample` made `using StatsBase` skip
# StatsBase.sample (a warning, then a MethodError in the learner's code).

module TutorChild

using TOML, Random, REPL

const USER_FILE = "main.jl"

# ---- shared ---------------------------------------------------------------------

unwrap_load_error(e) = e isa LoadError ? unwrap_load_error(e.error) : e

function user_frames(bt, file)
    out = String[]
    for fr in stacktrace(bt)
        # Method frames carry the path normalised (".\main.jl" on Windows,
        # "./main.jl" elsewhere); top-level frames carry it as given.
        replace(string(fr.file), r"^\.[\\/]" => "") == file || continue
        s = "  @ $(fr.func) at line $(fr.line)"
        isempty(out) || last(out) != s ? push!(out, s) : nothing
        length(out) >= 6 && break
    end
    return out
end

# `include_string` rethrows an error as a LoadError, and `catch_backtrace()` is
# then the backtrace of that rethrow (top level only). The original error and
# its backtrace, with the frames inside the learner's functions, are still on
# the exception stack: use the oldest entry's.
function original_backtrace()
    st = Base.current_exceptions()
    return isempty(st) ? catch_backtrace() : first(st).backtrace
end

function error_text(e, bt, file)
    io = IOBuffer()
    # invokelatest: the learner's code may define `showerror` (or `size` for an
    # array type in a BoundsError) after this function was compiled; without it
    # those methods are "too new" for this world and the message is wrong.
    Base.invokelatest(showerror, IOContext(io, :limit => true), unwrap_load_error(e))
    msg = String(take!(io))
    frames = user_frames(bt, file)
    if isempty(frames) && e isa LoadError && string(e.file) == file
        frames = ["  @ top level at line $(e.line)"]
    end
    return "ERROR: " * msg * (isempty(frames) ? "" : "\n" * join(frames, "\n"))
end

function short(x)
    s = try
        Base.invokelatest(repr, x; context = :limit => true)
    catch e
        e isa InterruptException && rethrow()
        "(a $(typeof(x)) that cannot be shown)"
    end
    return length(s) > 300 ? first(s, 300) * " …" : s
end
errmsg(e, n) = first(Base.invokelatest(sprint, showerror, e), n)

# ---- run ---------------------------------------------------------------------------

# A last value that is a figure (a Makie Figure, a Plots plot, a Gadfly plot)
# is saved as an image instead of printed: the REPL would open a window, here
# the file comes back to the caller (src/practice.jl collects *.png and *.svg
# files the code leaves in its directory). Plain data is never drawn: only
# values whose type comes from a package and that can render as an image.
const FIGURE_FILE = "figure"
function show_figure(val)
    parentmodule(typeof(val)) in (Base, Core) && return false
    val isa Union{AbstractArray,AbstractString,Number} && return false
    for (mime, ext) in ((MIME"image/png"(), "png"), (MIME"image/svg+xml"(), "svg"))
        Base.invokelatest(showable, mime, val) || continue
        open(io -> Base.invokelatest(show, io, mime, val), "$FIGURE_FILE.$ext", "w")
        println("[figure: $FIGURE_FILE.$ext]")
        return true
    end
    return false
end

function run_main(path, mode)
    code = read(path, String)
    Random.seed!(42)   # reproducible outputs; documented in the sandbox and the course
    ctx = IOContext(stdout, :limit => true, :displaysize => (24, 80), :module => Main)
    try
        val = mode == "repl" ? include_string(REPL.softscope, Main, code, USER_FILE) :
                               include_string(Main, code, USER_FILE)
        suppressed = endswith(rstrip(replace(code, r"#[^\n]*$"m => "")), ';')
        if val !== nothing && !suppressed && !show_figure(val)
            Base.invokelatest(show, ctx, MIME"text/plain"(), val)
            println()
        end
        flush(stdout)
        return 0
    catch e
        flush(stdout)
        println(error_text(e, original_backtrace(), USER_FILE))
        return 1
    end
end

# ---- grade --------------------------------------------------------------------------

function load_into(m::Module, code, file)
    try
        include_string(m, code, file)
        return nothing
    catch e
        return error_text(e, original_backtrace(), file)
    end
end

function call(f, args)
    try
        return (true, Base.invokelatest(f, args...))
    catch e
        e isa InterruptException && rethrow()
        return (false, e)
    end
end

# isapprox element by element through tuples and arrays of non-numbers
# (Base has no isapprox for tuples); an array of numbers goes to Base's
# isapprox as a whole, which is norm-wise; exact `isequal` for anything else.
approx(a::Tuple, b::Tuple, rtol) = length(a) == length(b) && all(approx(x, y, rtol) for (x, y) in zip(a, b))
approx(a::Pair, b::Pair, rtol) = approx(a.first, b.first, rtol) && approx(a.second, b.second, rtol)
function approx(a::AbstractArray, b::AbstractArray, rtol)
    size(a) == size(b) || return false
    eltype(a) <: Number && eltype(b) <: Number && return approx_num(a, b, rtol)
    return all(approx(x, y, rtol) for (x, y) in zip(a, b))
end
approx(a::Number, b::Number, rtol) = approx_num(a, b, rtol)
approx(a, b, rtol) = Base.invokelatest(isequal, a, b)
approx_num(a, b, rtol) = try
    Base.invokelatest(isapprox, a, b; rtol = rtol, nans = true)
catch
    Base.invokelatest(isequal, a, b)
end

function compare_case(fs, fr, mkargs, job)
    rargs = mkargs(); sargs = mkargs()
    rok, rv = call(fr, rargs)
    sok, sv = redirect_stdout(devnull) do
        call(fs, sargs)
    end
    # invokelatest: package types (a DataFrame) and learner types define
    # `isequal`/`==` in a newer world than this function's.
    # "custom": the problem's own `checker(got, expected) -> Bool`, for results
    # that have no meaningful `isequal` (a figure, a fitted model, samples).
    same_(a, b) = job["compare"] == "isapprox" ? approx(a, b, job["rtol"]) :
                  job["compare"] == "custom" ? Base.invokelatest(job["checker_fn"], a, b) === true :
                  Base.invokelatest(isequal, a, b)
    # The comparison runs the learner's types' methods (`isequal`, iteration of
    # a wrapper such as a PyDict), so it can throw: that is a wrong answer, not
    # a crash of the grading process.
    cmp_err = Ref("")
    same(a, b) = try
        same_(a, b)
    catch e
        e isa InterruptException && rethrow()
        cmp_err[] = errmsg(e, 200)
        false
    end
    if !rok
        sok && return (false, "should throw", "throws $(typeof(rv))", short(sv))
        typeof(sv) == typeof(rv) && return (true, "", "", "")
        return (false, "wrong error", "throws $(typeof(rv))", "throws $(typeof(sv)): " * errmsg(sv, 200))
    end
    sok || return (false, "threw", short(rv), "throws " * errmsg(sv, 300))
    same(sv, rv) || return isempty(cmp_err[]) ? (false, "wrong value", short(rv), short(sv)) :
        (false, "could not compare", short(rv), "$(short(sv))::$(typeof(sv)) (comparing it threw: $(cmp_err[]))")
    job["check_type"] && typeof(sv) != typeof(rv) &&
        return (false, "wrong type", "$(short(rv))::$(typeof(rv))", "$(short(sv))::$(typeof(sv))")
    if job["compare_args"] && !all(same(a, b) for (a, b) in zip(sargs, rargs))
        return (false, "argument differs", "arguments after the call: " * short(rargs), short(sargs))
    end
    return (true, "", "", "")
end

# Time per call: the minimum over samples, interleaving the two functions so a
# change in machine load affects both. Each sample runs enough calls to take at
# least ~1 ms, so the clock's resolution does not matter.
function calibrate(f::F, args::T) where {F,T}
    n = 1
    while true
        t = time_ns()
        for _ in 1:n
            Base.donotdelete(f(args...))
        end
        dt = time_ns() - t
        (dt >= 1_000_000 || n >= 1 << 22) && return n
        n *= dt < 100_000 ? 8 : 2
    end
end

function sample(f::F, args::T, n) where {F,T}
    t = time_ns()
    for _ in 1:n
        Base.donotdelete(f(args...))
    end
    return (time_ns() - t) / n
end

function sample_mutating(f::F, mk) where {F}
    a = mk()
    t = time_ns()
    Base.donotdelete(f(a...))
    return float(time_ns() - t)
end

function allocs(f::F, args::T) where {F,T}
    f(args...)
    best = typemax(Int)
    for _ in 1:3
        best = min(best, @allocated f(args...))
    end
    return best
end
function allocs_mutating(f::F, mk) where {F}
    a = mk(); f(a...)
    best = typemax(Int)
    for _ in 1:3
        a = mk()
        best = min(best, @allocated f(a...))
    end
    return best
end

function time_pair(fs::FS, fr::FR, mk, mutates::Bool; budget = 1.5, maxsamples = 25) where {FS,FR}
    bs = br = Inf
    t0 = time()
    if mutates
        for i in 1:maxsamples
            br = min(br, sample_mutating(fr, mk)); bs = min(bs, sample_mutating(fs, mk))
            i >= 5 && time() - t0 > budget && break
        end
    else
        args = mk()
        nr = calibrate(fr, args); ns = calibrate(fs, args)
        for i in 1:maxsamples
            br = min(br, sample(fr, args, nr)); bs = min(bs, sample(fs, args, ns))
            i >= 5 && time() - t0 > budget && break
        end
    end
    return bs, br
end

# Kinds: "concrete"; "small-union" (a concrete type or `nothing`/`missing`: a
# search result or iteration state, which the compiler splits cheaply and which
# is often the right design); "abstract-container" (concrete, but holds
# abstractly typed elements, e.g. Vector{Any}, Ref{Real}: every element is
# boxed); "abstract" (anything else, including Union{Int64, Float64}, the
# classic accumulator that starts as 0 and becomes a float).
function classify(t)
    t = Core.Compiler.widenconst(t)
    t === Union{} && return "concrete"
    # A local holding a type (`T = eltype(v)`, inferred `Type{Float64}`) is a
    # compile-time constant, not an instability, although Type{...} is not concrete.
    t isa DataType && t.name === Base.typename(Type) && return "concrete"
    if isconcretetype(t)
        if t isa DataType && (t <: AbstractArray || t <: Base.RefValue || t <: AbstractDict || t <: AbstractSet)
            for p in t.parameters
                p isa Type && !isconcretetype(p) && !(p isa Union && all(isconcretetype, Base.uniontypes(p))) &&
                    return "abstract-container"
            end
        end
        return "concrete"
    end
    if t isa Union
        parts = Base.uniontypes(t)
        benign = filter(p -> p === Nothing || p === Missing, parts)
        length(parts) <= 3 && all(isconcretetype, parts) && length(parts) - length(benign) == 1 &&
            return "small-union"
    end
    return "abstract"
end

# Locals of a typed CodeInfo that are not concretely typed (compiler-made
# slots, unnamed or starting with '#', are skipped).
function slot_locals(ci, fname)
    locals = Dict{String,Any}[]
    ci.slottypes isa Vector || return locals
    for (name, t) in zip(ci.slotnames, ci.slottypes)
        s = string(name)
        (isempty(s) || startswith(s, "#")) && continue
        k = classify(t)
        k == "concrete" || push!(locals, Dict("name" => s, "type" => string(Core.Compiler.widenconst(t)),
                                              "kind" => k, "function" => fname))
    end
    return locals
end

function inference(f, args, fname)
    types = Tuple{map(Core.Typeof, args)...}
    rts = Base.return_types(f, types)
    rt = isempty(rts) ? Any : reduce(Base.typejoin, rts)
    cis = code_typed(f, types; optimize = false)
    locals = isempty(cis) ? Dict{String,Any}[] : slot_locals(first(cis).first, fname)
    return string(rt), classify(rt), locals
end

# The other functions a module defines (helpers, and keyword-argument bodies,
# which Julia names `#f#12`), in every specialization compiled while grading:
# exactly the argument types the cases and the timing runs used. Inlined
# helpers are included (inference made a specialization before inlining).
# The entry's own positional method is `inference`'s job.
function helper_locals(m::Module, entry::Symbol; limit = 60)
    out = Dict{String,Any}[]
    seen = Set{Tuple{String,String,String}}()
    nspec = 0
    for n in names(m; all = true)
        n === entry && continue
        isdefined(m, n) || continue
        v = getfield(m, n)
        v isa Function || continue
        s = string(n)
        kwbody = match(r"^#+(.+?)#\d+$", s)
        fname = kwbody === nothing ? s : String(kwbody[1])
        startswith(fname, "#") && continue
        for meth in methods(v)
            meth.module === m || continue
            for mi in Base.specializations(meth)
                mi isa Core.MethodInstance && Base.isdispatchtuple(mi.specTypes) || continue
                (nspec += 1) > limit && return out
                cis = try
                    Base.code_typed_by_type(mi.specTypes; optimize = false)
                catch
                    continue
                end
                isempty(cis) && continue
                for l in slot_locals(first(cis).first, fname)
                    key = (fname, l["name"], l["type"])
                    key in seen || (push!(seen, key); push!(out, l))
                end
            end
        end
    end
    return out
end

# Called through invokelatest after `mkf` exists, so functions defined in the
# perf arguments (`x -> x + 1`) are visible to every call in here.
function perf_phase(fs, fr, job, mkf)
    mutates = job["mutates"]
    sizes = Dict{String,Any}[]
    rt = nothing
    for n in job["sizes"]
        mk = () -> Base.invokelatest(mkf, Xoshiro(job["seed"]), n)
        a = mk(); fr(a...); a = mk(); fs(a...)        # compile both before any measurement
        ts, tr = time_pair(fs, fr, mk, mutates)
        bs = mutates ? allocs_mutating(fs, mk) : allocs(fs, mk())
        br = mutates ? allocs_mutating(fr, mk) : allocs(fr, mk())
        push!(sizes, Dict("n" => n, "sub_ns" => ts, "ref_ns" => tr, "sub_bytes" => bs, "ref_bytes" => br))
        rt === nothing && (rt = mk())
    end
    entry = Symbol(job["entry"])
    rs, rsk, locals = inference(fs, rt, job["entry"])
    rr, rrk, ref_locals = inference(fr, rt, job["entry"])
    append!(locals, helper_locals(parentmodule(fs), entry))
    append!(ref_locals, helper_locals(parentmodule(fr), entry))
    return Dict("sizes" => sizes, "return_sub" => rs, "return_sub_kind" => rsk,
                "return_ref" => rr, "return_ref_kind" => rrk, "locals" => locals, "ref_locals" => ref_locals)
end

function grade_main(jobpath, outpath)
    job = TOML.parsefile(jobpath)
    res = Dict{String,Any}("status" => "ok", "phase" => "load")
    # Write to a temporary file and rename: a child killed mid-write (timeout,
    # out of memory) must leave no result or a whole one, never a partial file
    # the parent would read without a "status" key.
    save() = (open(io -> TOML.print(io, res; sorted = true), outpath * ".part", "w");
              mv(outpath * ".part", outpath; force = true))
    # Named modules bound in Main, not `Module()`: an anonymous module is rooted
    # only by local variables, and once those are dead the GC may free it while
    # the function types defined in it still point at it (observed: an access
    # violation in type hashing on 1.10.13 when both modules define `f`).
    R = Core.eval(Main, :(module Reference end))
    S = Core.eval(Main, :(module Submission end))
    # Case and perf arguments may use Random and the unit environment's packages
    # (e.g. build a DataFrame or a Date as an input).
    G = Core.eval(Main, Meta.parse("module Cases
using Random
" *
                                   join(["using " * p for p in get(job, "using", String[])], "
") * "
end"))
    err = load_into(R, job["reference"], "reference.jl")
    err === nothing || (res["status"] = "reference-error"; res["message"] = err; save(); return 2)
    err = redirect_stdout(devnull) do
        load_into(S, job["submission"], USER_FILE)
    end
    err === nothing || (res["status"] = "load-error"; res["message"] = err; save(); return 0)
    entry = Symbol(job["entry"])
    if !isdefined(S, entry) || !(getfield(S, entry) isa Base.Callable)
        res["status"] = "no-entry"; res["message"] = "Define a function named `$(job["entry"])`."
        save(); return 0
    end
    fs = getfield(S, entry); fr = getfield(R, entry)
    if job["compare"] == "custom"
        job["checker_fn"] = Core.eval(G, Meta.parse(job["checker"]))
    end

    # Correctness: explicit cases (shown to the learner) first, then generated ones.
    res["phase"] = "correctness"
    cases = Tuple{String,Any}[]
    for a in job["cases"]
        ex = Meta.parse("(" * a * ",)")
        push!(cases, (job["entry"] * "(" * a * ")", () -> Core.eval(G, ex)))
    end
    if !isempty(job["gen"])
        g = Core.eval(G, Meta.parse(job["gen"]))
        for t in Base.invokelatest(g, Xoshiro(job["seed"]))
            tt = t isa Tuple ? t : (t,)
            push!(cases, (job["entry"] * "(" * join(map(short, tt), ", ") * ")", () -> deepcopy(tt)))
        end
    end
    failures = Dict{String,Any}[]
    passed = 0
    # A problem about threads is graded on several threads with every case
    # repeated: a data race shows up as a run whose result differs.
    reps = get(job, "repeats", 1)
    for (i, (label, mk)) in enumerate(cases)
        ok, reason, expected, got = compare_case(fs, fr, mk, job)
        k = 1
        while ok && k < reps
            k += 1
            ok, reason, expected, got = compare_case(fs, fr, mk, job)
            ok || (reason = "result changed on run $k of $reps")
        end
        if ok
            passed += 1
        elseif length(failures) < 3
            push!(failures, Dict("case" => i, "input" => label, "reason" => reason,
                                 "expected" => expected, "got" => got, "shown" => i <= length(job["cases"])))
        end
    end
    res["correctness"] = Dict("passed" => passed, "total" => length(cases), "failures" => failures,
                              "explicit" => length(job["cases"]))
    save()
    if passed == length(cases) && !isempty(job["perf_args"])
        res["phase"] = "performance"
        save()
        # An exception here is a measurement failure (bad perf args, an error
        # at the perf sizes), never "slow": record it so the grader can say so.
        try
            mkf = Core.eval(G, Meta.parse("(rng, n) -> (" * job["perf_args"] * ",)"))
            res["perf"] = Base.invokelatest(perf_phase, fs, fr, job, mkf)
        catch e
            e isa InterruptException && rethrow()
            res["perf_error"] = error_text(e, original_backtrace(), USER_FILE)
        end
    end
    res["phase"] = "done"
    save()
    return 0
end

function main(args)
    if length(args) == 3 && args[1] == "run"
        return run_main(args[2], args[3])
    elseif length(args) == 3 && args[1] == "grade"
        return grade_main(args[2], args[3])
    end
    println(stderr, "usage: sandbox.jl run <code.jl> <repl|file> | grade <job.toml> <result.toml>")
    return 2
end

end # module TutorChild

# contained.jl includes this file and calls `TutorChild.main` itself.
isdefined(Main, :FILES_BEGIN) || exit(TutorChild.main(ARGS))
