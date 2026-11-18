# The test-to-hole map and mutation testing, both *measured*:
#
# * deps[h]: the testsets that fail when exactly hole `h` is opened (TODO body)
#   in the otherwise complete reference. This is the "coverage" matrix Ochiai uses.
# * mutants: each plausible-but-wrong body from holes.toml must make at least one
#   test fail, or the specification is too weak (test engineer's objection).
#   A project's mutants.toml adds seeded mutants (find/replace in the
#   reference), held to the same rule.
# * the fill check: each starter stage must fail only at its blanks (see
#   `stage_problems`).
#
# Every run is a fresh process (see runner.jl), so runs cannot contaminate each
# other. Runs are independent and executed 4 at a time; each is single-threaded,
# so the result does not depend on scheduling.

module HoleMap

using TOML
using ..Scaffold, ..Runner

export compute_holemap, holemap_toml, load_holemap

"""Copy the reference package to a temp dir with `opened` holes replaced."""
function materialize(p::Scaffold.ProjectSpec, opened::Dict{String,String})
    dir = mktempdir()
    ref = Scaffold.reference_dir(p)
    for rel in Scaffold.package_files(p)
        src = read(joinpath(ref, rel), String)
        if endswith(rel, ".jl") && startswith(rel, "src/")
            mine = Dict(id => b for (id, b) in opened if any(h -> h.id == id && h.file == rel, p.holes))
            src = Scaffold.render_source(src, rel, mine)
        end
        mkpath(dirname(joinpath(dir, rel)))
        write(joinpath(dir, rel), src)
    end
    return dir
end

failing(rep::Runner.TestReport) = sort!([t.name for t in rep.testsets if !Runner.ok(t)])
all_names(rep::Runner.TestReport) = sort!([t.name for t in rep.testsets])

function run_variant(p, opened)
    dir = materialize(p, opened)
    rep = Runner.run_tests(dir; timeout = 300)
    rm(dir; recursive = true, force = true)
    return rep
end

"""
A seeded mutant (projects/<p>/mutants.toml, optional): one bug injected into the
reference by replacing `find`, which must occur exactly once in src/<file>, with
`replace`. Unlike a hole's trivial bodies it is not tied to a hole, so it can
sit in code no starter opens (a gate constant, say).
"""
struct Seeded
    id::String
    description::String
    file::String                 # relative to the reference's src/
    find::String
    replace::String
end

function load_seeded(p::Scaffold.ProjectSpec)
    path = joinpath(p.dir, "mutants.toml")
    isfile(path) || return Seeded[]
    ms = [Seeded(m["id"], m["description"], m["file"], m["find"], m["replace"])
          for m in get(TOML.parsefile(path), "mutant", Any[])]
    allunique(m.id for m in ms) || error("duplicate mutant ids in $path")
    return ms
end

"Copy the reference with seeded mutant `m` applied; errors unless `find` occurs exactly once."
function materialize_seeded(p::Scaffold.ProjectSpec, m::Seeded)
    dir = materialize(p, Dict{String,String}())
    path = joinpath(dir, "src", m.file)
    isfile(path) || error("mutant $(m.id): no reference file src/$(m.file)")
    src = read(path, String)
    n = length(findall(m.find, src))
    n == 1 || error("mutant $(m.id): `find` occurs $n times in src/$(m.file) (must be once)")
    write(path, replace(src, m.find => m.replace))
    return dir
end

"""
The fill check for starter `stage`: run the reference with every hole of that
stage opened. A starter must fail only at its blanks: no crash, every failing
testset reaches a TODO of a hole opened at this stage, and it fails no testset
that the measured map of the opened holes does not predict.
"""
function stage_problems(p::Scaffold.ProjectSpec, stage::Int, rep::Runner.TestReport, deps)
    out = String[]
    opened = Set(h.id for h in p.holes if h.stage <= stage)
    isempty(rep.crash) || push!(out, "stage $stage starter crashes: $(rep.crash)")
    predicted = Set{String}()
    for id in opened
        union!(predicted, get(deps, id, String[]))
    end
    for t in rep.testsets
        Runner.ok(t) && continue
        isempty(t.holes) && push!(out, "stage $stage starter fails `$(t.name)` without reaching a hole: $(join(t.messages, "; "))")
        extra = setdiff(t.holes, opened)
        isempty(extra) || push!(out, "stage $stage starter reaches holes it does not open in `$(t.name)`: $(join(extra, ", "))")
        t.name in predicted || push!(out, "stage $stage starter fails `$(t.name)`, which no opened hole's map predicts")
    end
    return out
end

"""
    compute_holemap(p; ntasks = 4) -> Dict

Returns a Dict ready for TOML: `testsets`, `deps`, `mutants`, `problems`, and
`seeded` when the project has a mutants.toml. The per-stage fill check adds
only to `problems` (a passing project's file does not change).
"""
function compute_holemap(p::Scaffold.ProjectSpec; ntasks::Int = 4, log = stdout)
    # (kind, id, i, make): kind is :reference, :hole (i = 0: TODO, else trivial i),
    # :stage (i = the stage) or :seeded; make() returns the package dir to test.
    jobs = Tuple{Symbol,String,Int,Function}[(:reference, "", 0, () -> materialize(p, Dict{String,String}()))]
    for h in p.holes
        push!(jobs, (:hole, h.id, 0, () -> materialize(p, Dict(h.id => Scaffold.todo_body(h.id)))))
        for (i, body) in enumerate(h.trivial_bodies)
            push!(jobs, (:hole, h.id, i, () -> materialize(p, Dict(h.id => body))))
        end
    end
    for s in p.stages
        opened = Dict(h.id => Scaffold.todo_body(h.id) for h in p.holes if h.stage <= s)
        push!(jobs, (:stage, "", s, () -> materialize(p, opened)))
    end
    seeded = load_seeded(p)
    for m in seeded
        push!(jobs, (:seeded, m.id, 0, () -> materialize_seeded(p, m)))
    end
    label(kind, id, i) = kind === :reference ? "reference" : kind === :stage ? "stage $i starter" :
                         kind === :seeded ? "mutant $id" : "$id/$(i == 0 ? "todo" : "trivial-$i")"
    reports = asyncmap(jobs; ntasks) do (kind, id, i, make)
        dir = make()
        rep = Runner.run_tests(dir; timeout = 300)
        rm(dir; recursive = true, force = true)
        println(log, "  ran ", label(kind, id, i), ": ", length(failing(rep)), " failing testsets",
                isempty(rep.crash) ? "" : " (crash: $(rep.crash))")
        rep
    end
    problems = String[]
    ref = reports[1]
    isempty(failing(ref)) && isempty(ref.crash) ||
        push!(problems, "reference does not pass: $(join(failing(ref), "; ")) $(ref.crash)")
    deps = Dict{String,Any}()
    mutants = Dict{String,Any}()
    seeded_out = Dict{String,Any}()
    for (k, (kind, id, i, _)) in enumerate(jobs)
        kind === :hole || kind === :seeded || continue
        rep = reports[k]
        f = failing(rep)
        if kind === :hole && i == 0
            deps[id] = f
            isempty(f) && push!(problems, "opening hole `$id` makes no test fail")
            continue
        end
        caught = !isempty(f) || !isempty(rep.crash)
        what = kind === :seeded ? "mutant `$id` (mutants.toml)" : "trivial body $i of hole `$id`"
        if kind === :seeded
            seeded_out[id] = Dict("failing_testsets" => length(f), "caught" => caught, "timed_out" => rep.timed_out)
        else
            push!(get!(mutants, id, Any[]), Dict("trivial" => i, "failing_testsets" => length(f),
                                                 "caught" => caught, "timed_out" => rep.timed_out))
        end
        caught || push!(problems, "$what passes every test (mutant survived)")
        # A mutant must be caught by a failing test, quickly: a student with
        # that body would otherwise wait for the timeout.
        rep.timed_out && push!(problems, "$what is only caught by the timeout")
    end
    for (k, (kind, _, s, _)) in enumerate(jobs)
        kind === :stage && append!(problems, stage_problems(p, s, reports[k], deps))
    end
    d = Dict{String,Any}("julia" => string(VERSION), "testsets" => all_names(ref), "deps" => deps,
                         "mutants" => mutants, "problems" => problems)
    isempty(seeded) || (d["seeded"] = seeded_out)
    return d
end

function holemap_toml(d::Dict)
    io = IOBuffer()
    println(io, "# Generated by `tutor holemap <project>`. Do not edit.")
    println(io, "# deps.<hole> = testsets that fail when only that hole is opened in the reference.")
    TOML.print(io, d; sorted = true)
    return String(take!(io))
end

function load_holemap(p::Scaffold.ProjectSpec)
    path = joinpath(p.dir, "holemap.toml")
    isfile(path) || return nothing
    return TOML.parsefile(path)
end

end # module HoleMap
