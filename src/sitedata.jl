# Data for the static website (site/, built with Quarto + a React app in web/).
#
# The site cannot run Julia, so everything it shows is exported from the same
# verified sources the CLI uses: lesson keys checked by `tutor lessons verify`,
# rule metadata and an example finding from the checker, the measured hole map,
# and the explain golden outputs. `tutor site-data --check` (in verify_all.sh)
# fails when the committed JSON is stale, like every other generated file.
#
# JSON is written by a small deterministic writer (sorted keys) so the tutor
# stays stdlib-only.

module SiteData

using TOML
using ..Checker, ..Scaffold, ..HoleMap, ..Lessons, ..Fixtures

export site_data, to_json

const TUTOR_ROOT = normpath(joinpath(@__DIR__, ".."))

# ---- JSON ----------------------------------------------------------------------

function json_string(io::IO, s::AbstractString)
    print(io, '"')
    for c in s
        if c == '"';      print(io, "\\\"")
        elseif c == '\\'; print(io, "\\\\")
        elseif c == '\n'; print(io, "\\n")
        elseif c == '\r'; print(io, "\\r")
        elseif c == '\t'; print(io, "\\t")
        elseif c < ' ';   print(io, "\\u", lpad(string(UInt32(c), base = 16), 4, '0'))
        else              print(io, c)
        end
    end
    print(io, '"')
end

write_json(io::IO, x::AbstractString, _) = json_string(io, x)
write_json(io::IO, x::Bool, _) = print(io, x ? "true" : "false")
write_json(io::IO, x::Integer, _) = print(io, x)
write_json(io::IO, x::AbstractFloat, _) = isfinite(x) ? print(io, repr(Float64(x))) : print(io, "null")
write_json(io::IO, ::Nothing, _) = print(io, "null")
write_json(io::IO, x::Symbol, d) = write_json(io, String(x), d)
function write_json(io::IO, x::AbstractVector, d)
    isempty(x) && return print(io, "[]")
    print(io, "[\n")
    for (i, v) in enumerate(x)
        print(io, "  "^(d + 1)); write_json(io, v, d + 1)
        print(io, i < length(x) ? ",\n" : "\n")
    end
    print(io, "  "^d, "]")
end
function write_json(io::IO, x::AbstractDict, d)
    isempty(x) && return print(io, "{}")
    ks = sort!([string(k) for k in keys(x)])
    vals = Dict(string(k) => v for (k, v) in x)
    print(io, "{\n")
    for (i, k) in enumerate(ks)
        print(io, "  "^(d + 1)); json_string(io, k); print(io, ": "); write_json(io, vals[k], d + 1)
        print(io, i < length(ks) ? ",\n" : "\n")
    end
    print(io, "  "^d, "}")
end
to_json(x) = (io = IOBuffer(); write_json(io, x, 0); println(io); String(take!(io)))

# ---- content -------------------------------------------------------------------

function lessons_data()
    out = Any[]
    for l in Lessons.load_lessons()
        checks = Any[]
        for c in l.checks
            mis = Any[Dict("option" => k, "id" => v[1], "feedback" => v[2]) for (k, v) in sort!(collect(c.misconceptions))]
            push!(checks, Dict("id" => c.id, "prompt" => c.prompt, "code" => c.code, "options" => c.options,
                               "answer" => c.answer, "hint" => c.hint, "explanation" => c.explanation,
                               "misconceptions" => mis))
        end
        push!(out, Dict("id" => l.id, "title" => l.title, "kcs" => l.kcs, "prerequisites" => l.prerequisites,
                        "verified_on" => l.verified_on, "body" => strip(l.body), "checks" => checks))
    end
    return out
end

"""Rule metadata plus one example: the first positive case and the finding it produces."""
function rules_data()
    cases = Module(:ExportCases)
    Base.include(cases, joinpath(TUTOR_ROOT, "test", "checker_cases.jl"))
    CASES = getfield(cases, :CASES)
    out = Any[]
    for r in Checker.RULES
        m = Checker.meta(r)
        ex = haskey(CASES, m.id) ? first(CASES[m.id].positive) : nothing
        fs =ex === nothing ? Checker.Finding[] : filter(f -> f.rule == m.id, Checker.check_source(ex, "example.jl"))
        push!(out, Dict("id" => m.id, "name" => m.name, "kc" => m.kc, "severity" => string(m.severity),
                        "fp_risk" => m.fp_risk, "measured_by" => m.measured_by, "hints" => collect(m.hints),
                        "example" => ex === nothing ? nothing :
                            Dict("code" => ex, "message" => isempty(fs) ? nothing : first(fs).message,
                                 "line" => isempty(fs) ? nothing : first(fs).line)))
    end
    return out
end

"""The docstring above each hole in the reference: it is the specification (no answer)."""
function hole_specs(p::Scaffold.ProjectSpec)
    specs = Dict{String,String}()
    for h in p.holes
        lines = readlines(joinpath(Scaffold.reference_dir(p), h.file))
        i = findfirst(l -> strip(l) == "# HOLE: $(h.id)", lines)
        i === nothing && continue
        j = findnext(l -> startswith(l, "function "), lines, i + 1)
        doc = lines[i+1:j-1]
        if !isempty(doc) && strip(first(doc)) == "\"\"\"" && strip(last(doc)) == "\"\"\""
            specs[h.id] = join(doc[2:end-1], '\n')
        end
    end
    return specs
end

function project_data(name::String)
    p = Scaffold.load_project(joinpath(TUTOR_ROOT, "projects", name))
    specs = hole_specs(p)
    hm = HoleMap.load_holemap(p)
    base = TOML.parsefile(joinpath(p.dir, "measure_baseline.toml"))
    holes = Any[Dict("id" => h.id, "stage" => h.stage, "kc" => h.kc, "summary" => h.summary,
                     "file" => h.file, "spec" => get(specs, h.id, ""),
                     "trivial_bodies" => length(h.trivial_bodies)) for h in p.holes]
    mutants = Dict(id => [Dict("trivial" => m["trivial"], "caught" => m["caught"],
                               "failing_testsets" => m["failing_testsets"]) for m in ms]
                   for (id, ms) in hm["mutants"])
    fixtures = Any[]
    for f in Fixtures.load_fixtures(p)
        path = Fixtures.golden_path(p, f)
        push!(fixtures, Dict("name" => f.name, "hole" => f.hole, "stage" => f.stage,
                             "misconception" => f.misconception, "description" => f.description,
                             "expect_start" => f.expect_start, "body" => f.body,
                             "golden" => isfile(path) ? read(path, String) : ""))
    end
    return Dict("name" => p.name, "package" => p.package, "stages" => p.stages, "holes" => holes,
                "testsets" => hm["testsets"], "deps" => hm["deps"], "mutants" => mutants,
                "problems" => hm["problems"], "baseline" => base, "fixtures" => fixtures)
end

function site_data()
    projects = sort!([d for d in readdir(joinpath(TUTOR_ROOT, "projects"))
                      if isfile(joinpath(TUTOR_ROOT, "projects", d, "holes.toml"))])
    return Dict("julia" => string(VERSION),
                "generated_by" => "tutor site-data (do not edit; regenerate)",
                "lessons" => lessons_data(), "rules" => rules_data(),
                "projects" => Any[project_data(n) for n in projects])
end

end # module SiteData
