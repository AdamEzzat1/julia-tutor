# Child-process entry point: run a package's tests and write per-testset results.
# Usage: julia --project=<pkgdir> run_tests.jl <pkgdir> <out.toml>
#
# Depends on Test internals (DefaultTestSet.results / n_passed, Fail/Error
# fields). Those are not public API: re-verify on every Julia upgrade (the
# runner's own tests do).

using Test, TOML

const PKGDIR, OUT = ARGS[1], ARGS[2]
const HOLE_RE = r"TODO\(hole:([a-z][a-z0-9_]*)\)"

# A printed Expr with a macro call carries its LineNumberNode as
# `#= /abs/path/runtests.jl:140 =#`: noise for the student, and it leaks the
# absolute path of their machine into explain output. Drop it.
const LINENODE_RE = r"#= .*?:\d+ =# ?"

# Machine paths in messages (the package dir, this run's private depot, the temp
# and home dirs) become placeholders: they leak the student's machine layout and
# change on every run (the private depot is a fresh temp dir), which would break
# golden outputs. Longest first, in raw, `\\`-escaped and `/` spellings.
const PATH_PLACEHOLDERS = let
    pairs = [PKGDIR => "<pkg>", DEPOT_PATH[1] => "<depot>", tempdir() => "<tmp>", homedir() => "<home>"]
    out = Pair{String,String}[]
    for (p, ph) in sort(pairs; by = x -> -length(first(x)))
        p = rstrip(p, ['/', '\\'])
        isempty(p) && continue
        for v in unique([p, replace(p, '\\' => "\\\\"), replace(p, '\\' => '/')])
            push!(out, v => ph)
        end
    end
    out
end
# Base's "Failed to precompile P [uuid] to \"<random temp file>\"": the target
# file name is random per run and says nothing useful; keep the rest.
const PRECOMPILE_TARGET_RE = r"(Failed to precompile [^\[]*\[[0-9a-f-]+\]) to \"[^\"]*\"\.?"
scrub(s::AbstractString) = replace(foldl((acc, pr) -> replace(acc, pr), PATH_PLACEHOLDERS; init = String(s)),
                                   PRECOMPILE_TARGET_RE => s"\1.")

function firstline(s::AbstractString; maxlen = 300)
    l = strip(scrub(replace(first(split(s, '\n')), LINENODE_RE => "")))
    return length(l) > maxlen ? first(l, maxlen) * "…" : String(l)
end

function relsource(src)
    src isa LineNumberNode || return "?"
    file = replace(string(src.file), '\\' => '/')
    root = replace(PKGDIR, '\\' => '/')
    startswith(file, root) && (file = lstrip(file[ncodeunits(root)+1:end], '/'))
    return "$file:$(src.line)"
end

function collect!(entries, ts::Test.DefaultTestSet, path::String)
    name = isempty(path) ? ts.description : path * "/" * ts.description
    msgs = String[]
    holes = String[]
    failed = errored = todo_errors = 0   # todo_errors: errors that are a hole's TODO
    for r in ts.results
        if r isa Test.DefaultTestSet
            collect!(entries, r, name)
        elseif r isa Test.Fail
            failed += 1
            push!(msgs, "$(relsource(r.source)) FAIL $(firstline(r.orig_expr))" *
                        (r.data === nothing ? "" : "  evaluated: $(firstline(string(r.data)))"))
        elseif r isa Test.Error
            errored += 1
            text = string(r.value)
            occursin(HOLE_RE, text) && (todo_errors += 1)
            for m in eachmatch(HOLE_RE, text * "\n" * string(r.backtrace))
                m[1] in holes || push!(holes, m[1])
            end
            push!(msgs, "$(relsource(r.source)) ERROR $(firstline(text))")
        end
    end
    if ts.n_passed + failed + errored > 0
        push!(entries, Dict("name" => name, "passed" => ts.n_passed, "failed" => failed,
                            "errored" => errored, "todo_errors" => todo_errors, "messages" => msgs[1:min(end, 5)],
                            "holes" => sort!(holes)))
    end
    return entries
end

root = Test.DefaultTestSet("")
crash = ""
Test.push_testset(root)
try
    include(joinpath(PKGDIR, "test", "runtests.jl"))
catch err
    global crash = firstline(sprint(showerror, err); maxlen = 2000)
finally
    Test.pop_testset()
end

entries = Dict{String,Any}[]
for r in root.results
    r isa Test.DefaultTestSet && collect!(entries, r, "")
end
for r in root.results           # failures/errors recorded directly on the root
    if r isa Test.Error
        global crash = crash * " " * firstline(string(r.value))
    end
end
open(OUT, "w") do io
    TOML.print(io, Dict("testsets" => entries, "crash" => crash))
end
