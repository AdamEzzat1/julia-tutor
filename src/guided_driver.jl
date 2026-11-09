# The guided-project driver: runs inside the sandbox (container or plain child),
# never in the tutor process. `Guided.driver_source` prepends one line,
#     GUIDED_JOB = "<base64 of a TOML job>"
# (not const: `main` clears it, and deletes main.jl, before any test runs).
# and the result is sent as `main.jl` to the existing child's `run <file> file`
# mode, so the image needs nothing new.
#
# The job holds the files (relative path => content), the package name, the
# implementations (a directory holding `src/<Package>.jl`) and the runs: one
# test file against one implementation. Each implementation is included into a
# fresh module; each run evaluates the test file in another fresh module where
# the package name is bound to that implementation, with `using Pkg` and
# `import Pkg: f` rewritten on the parsed tree to `using .Pkg`. A recording
# test set collects every result without throwing. After every run the driver
# rewrites `result.toml` and prints a stage marker, so a timeout still says how
# far it got.

module GuidedDriver

using Test, TOML, Random, Base64

const STAGE = "<<<guided-stage>>>"
const MAX_MSG = 1500
const MAX_MSGS = 5

# ---- a test set that records instead of throwing -------------------------------------

mutable struct RecordingTestSet <: Test.AbstractTestSet
    description::String
    results::Vector{Any}
end
RecordingTestSet(desc::AbstractString; kw...) = RecordingTestSet(String(desc), Any[])
Test.record(ts::RecordingTestSet, r) = (push!(ts.results, r); r)
function Test.finish(ts::RecordingTestSet)
    if Test.get_testset_depth() > 0
        Test.record(Test.get_testset(), ts)
    end
    return ts
end

# ---- rewriting `using Pkg` to the implementation bound in the test module -------------

function relative_path(p, pkg::Symbol)
    if p isa Expr && p.head === :as && !isempty(p.args)   # import Pkg as P
        return Expr(:as, relative_path(p.args[1], pkg), p.args[2:end]...)
    end
    if p isa Expr && p.head === :. && !isempty(p.args) && p.args[1] === pkg
        return Expr(:., :., p.args...)
    end
    return p
end

function rewrite(ex, pkg::Symbol)
    ex isa Expr || return ex
    if ex.head === :using || ex.head === :import
        args = map(ex.args) do a
            if a isa Expr && a.head === :(:)
                Expr(:(:), relative_path(a.args[1], pkg), a.args[2:end]...)
            else
                relative_path(a, pkg)
            end
        end
        return Expr(ex.head, args...)
    end
    ex.head === :quote && return ex
    return Expr(ex.head, (rewrite(a, pkg) for a in ex.args)...)
end

# ---- messages ----------------------------------------------------------------------------

function clip(s::AbstractString, n = MAX_MSG)
    ncodeunits(s) <= n ? String(s) : String(s[1:prevind(s, n)]) * " …"
end

"""Paths under the job root shown relative to it (`student/test/runtests.jl:12`)."""
scrub(s::AbstractString, root::AbstractString) =
    replace(replace(s, root * "/" => ""), replace(root, '/' => '\\') * "\\" => "")

function message(r, root)
    io = IOBuffer()
    try
        show(io, r)
    catch
        print(io, typeof(r))
    end
    return clip(scrub(String(take!(io)), root))
end

"""Short one-line description of an Error result: the exception type and first line."""
function error_head(r::Test.Error)
    v = r.value
    s = v isa AbstractString ? v : string(v)
    first_line = split(s, '\n'; limit = 2)[1]
    return clip(first_line, 300)
end

# Flatten the tree: every named test set with its own direct results.
function flatten!(out, ts::RecordingTestSet, prefix::String, root)
    name = isempty(prefix) ? ts.description : prefix * "/" * ts.description
    d = Dict{String,Any}("name" => name, "passed" => 0, "failed" => 0, "errored" => 0,
                         "messages" => String[], "errors" => String[])
    push!(out, d)
    for r in ts.results
        if r isa RecordingTestSet
            flatten!(out, r, name, root)
        elseif r isa Test.Pass
            d["passed"] += 1
        elseif r isa Test.Error
            d["errored"] += 1
            length(d["messages"]) < MAX_MSGS && push!(d["messages"], message(r, root))
            length(d["errors"]) < MAX_MSGS && push!(d["errors"], scrub(error_head(r), root))
        elseif r isa Test.Broken
            # @test_broken / @test_skip: neither a pass nor a failure
        elseif r isa Test.Result
            # Test.Fail, and every other failing result (`@test_logs` records a
            # Test.LogTestFailure, which is not a Test.Fail).
            d["failed"] += 1
            length(d["messages"]) < MAX_MSGS && push!(d["messages"], message(r, root))
        end
    end
    return out
end

# ---- implementations and runs -----------------------------------------------------------------

function error_text(e, root)
    io = IOBuffer()
    showerror(io, e)
    return clip(scrub(String(take!(io)), root))
end

"""Include `<dir>/src/<pkg>.jl` into a fresh module; the package module or an error string."""
function load_impl(root::String, dir::String, pkg::Symbol)
    parent = Module(:Impl)
    file = joinpath(root, dir, "src", string(pkg) * ".jl")
    isfile(file) || return "there is no src/$(pkg).jl"
    try
        Base.include(parent, file)
    catch e
        e isa InterruptException && rethrow()
        return error_text(e, root)
    end
    isdefined(parent, pkg) && getfield(parent, pkg) isa Module ||
        return "src/$(pkg).jl does not define `module $(pkg)`"
    return getfield(parent, pkg)
end

function run_tests(root::String, impl::Module, testfile::String, pkg::Symbol, seed::Int)
    T = Module(:Tests)
    Core.eval(T, :(const $pkg = $impl))
    mapexpr = ex -> rewrite(ex, pkg)
    # Nested `include("x.jl")` in the test file goes through the same rewrite.
    Core.eval(T, :(include(p::AbstractString) = $(Base.include)($mapexpr, $T, p)))
    rootset = RecordingTestSet("")
    Random.seed!(seed)
    toplevel = ""
    wd = pwd()   # a test file may `cd(@__DIR__)`; the next run must not inherit it
    Test.push_testset(rootset)
    try
        Base.include(mapexpr, T, joinpath(root, testfile))
    catch e
        e isa InterruptException && rethrow()
        toplevel = error_text(e, root)
    finally
        Test.pop_testset()
        cd(wd)
    end
    sets = flatten!(Any[], rootset, "", root)
    return Dict{String,Any}("testsets" => sets, "toplevel_error" => toplevel,
                            "total" => sum(s -> s["passed"] + s["failed"] + s["errored"], sets))
end

write_result(path, res) = open(io -> TOML.print(io, res; sorted = true), path, "w")

"""
Write one implementation's files (`<impl>/...`, plus `acceptance/` when one of
its runs is an acceptance test) into a fresh directory. Only that
implementation is on disk while its tests run, so a student's test cannot read
a sibling's source (the reference's, say) or include the acceptance tests on a
mutant (a student check runs acceptance tests on the student's code only).
"""
function materialize(files, impl::String, with_acceptance::Bool)
    root = replace(mktempdir(), '\\' => '/')
    for (rel, content) in files
        top = split(rel, '/'; limit = 2)[1]
        (top == impl || (with_acceptance && top == "acceptance")) || continue
        path = joinpath(root, split(rel, '/')...)
        mkpath(dirname(path))
        write(path, content)
    end
    return root
end

function main(jobtext::String)
    job = TOML.parse(String(base64decode(jobtext)))
    # The job (reference, mutants, acceptance tests) must not stay reachable from test code.
    isdefined(Main, :GUIDED_JOB) && Core.eval(Main, :(GUIDED_JOB = nothing))
    rm("main.jl"; force = true)   # this program, job included; the child sent it, so it is not sent back
    resfile = abspath("result.toml")
    for rel in keys(job["files"])
        (occursin("..", rel) || startswith(rel, "/")) && error("bad path $rel")
    end
    pkg = Symbol(job["package"])
    res = Dict{String,Any}("runs" => Any[], "complete" => false)
    write_result(resfile, res)
    cur = ""; root = ""; impl = nothing
    for run in job["runs"]
        label = run["label"]
        println(STAGE, " ", label)
        flush(stdout)
        dir = run["impl"]
        if dir != cur   # runs are grouped by implementation
            isempty(root) || rm(root; recursive = true, force = true)
            acc = any(x -> x["impl"] == dir && startswith(x["tests"], "acceptance/"), job["runs"])
            root = materialize(job["files"], dir, acc)
            impl = load_impl(root, dir, pkg)
            cur = dir
        end
        r = Dict{String,Any}("label" => label, "impl" => dir, "tests" => run["tests"])
        if impl isa String
            r["load_error"] = impl
        elseif !isfile(joinpath(root, run["tests"]))
            r["tests_missing"] = true
        else
            merge!(r, run_tests(root, impl, run["tests"], pkg, job["seed"]))
            # Show `test/runtests.jl:12`, not the neutral implementation name.
            if dir != "student"
                un(s) = replace(s, dir * "/" => "", dir * "\\" => "")
                r["toplevel_error"] = un(r["toplevel_error"])
                for s in r["testsets"]
                    s["messages"] = map(un, s["messages"]); s["errors"] = map(un, s["errors"])
                end
            end
        end
        push!(res["runs"], r)
        write_result(resfile, res)
    end
    isempty(root) || rm(root; recursive = true, force = true)
    res["complete"] = true
    write_result(resfile, res)
    println(STAGE, " done")
    return nothing
end

end # module GuidedDriver

GuidedDriver.main(GUIDED_JOB)
nothing
