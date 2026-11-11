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
using ..Checker, ..Scaffold, ..HoleMap, ..Lessons, ..Fixtures, ..Course
using ..JSON: to_json

export site_data, course_data, to_json

const TUTOR_ROOT = normpath(joinpath(@__DIR__, ".."))

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


# ---- courses (site/data/courses.json + course-<id>.json) ------------------------------
#
# Reference solutions and generated test cases stay out of the site data: the
# browser gets prompts, starters, hints, the reference's output on the shown
# cases, and the recorded example outputs. Grading happens in `tutor serve`.

"""
Figures recorded for the course (course/outputs/figures/<unit>/<file>) as
site paths => bytes; `tutor site-data` copies them to site/assets/figures/.
"""
function course_figures()
    root = joinpath(Course.COURSE_DIR, "outputs", "figures")
    out = Pair{String,Vector{UInt8}}[]
    isdir(root) || return out
    for u in sort!(readdir(root)), f in sort!(readdir(joinpath(root, u)))
        push!(out, "assets/figures/$u/$f" => read(joinpath(root, u, f)))
    end
    return out
end

"""Exact package versions of a pinned course environment, from its Manifest."""
function env_packages(env::String)
    dir = Course.env_dir(env)
    proj = TOML.parsefile(joinpath(dir, "Project.toml"))
    man = joinpath(dir, "Manifest.toml")
    deps = sort!(collect(keys(get(proj, "deps", Dict()))))
    m = isfile(man) ? get(TOML.parsefile(man), "deps", Dict()) : Dict()
    return Any[Dict("name" => d, "version" => haskey(m, d) ? get(m[d][1], "version", "stdlib") : "?") for d in deps]
end

function course_data()
    units = Course.load_course()
    cidx = Course.course_index(Course.load_courses())
    out = Any[]
    for u in units
        rec = Course.load_outputs(u)
        exs = get(rec, "examples", Dict()); sm = get(rec, "samples", Dict())
        sections = Any[]
        for s in u.sections
            examples = Any[]
            for e in s.examples
                r = get(exs, Course.example_key(e.code, e.mode), nothing)
                push!(examples, Dict("code" => rstrip(e.code), "caption" => e.caption, "notice" => e.notice, "mode" => e.mode,
                                     "check" => e.check, "output" => r === nothing ? nothing : r["output"],
                                     "ok" => r === nothing ? nothing : r["ok"],
                                     "images" => r === nothing ? Any[] :
                                         Any["assets/figures/$(u.id)/$f" for f in get(r, "images", Any[])]))
            end
            questions = Any[Dict("kind" => q.kind, "prompt" => strip(q.prompt), "code" => rstrip(q.code),
                                 "choices" => q.choices, "answer" => q.answer, "explain" => strip(q.explain),
                                 "misconceptions" => q.misconceptions) for q in s.questions]
            push!(sections, Dict("title" => s.title, "body" => strip(s.body), "examples" => examples,
                                 "questions" => questions))
        end
        problems = Any[Dict("id" => p.id, "title" => p.title, "difficulty" => p.difficulty, "kcs" => p.kcs,
                            "prompt" => strip(p.prompt), "entry" => p.entry, "starter" => p.starter,
                            "hints" => p.hints, "samples" => get(sm, p.id, Any[]),
                            "compare" => p.compare, "rtol" => p.rtol, "check_type" => p.check_type,
                            "random_cases" => !isempty(p.gen),
                            "perf" => p.perf === nothing ? nothing :
                                Dict("sizes" => p.perf.sizes, "mutates" => p.perf.mutates))
                       for p in u.problems]
        # prerequisites as unit ids (unique across courses); each unit says its course
        push!(out, Dict("id" => u.id, "title" => u.title, "track" => u.track, "env" => u.env,
                        "course" => get(cidx, u.id, nothing),
                        "status" => u.status, "summary" => strip(u.summary), "kcs" => u.kcs,
                        "prerequisites" => Course.prereq_unit.(u.prerequisites), "outline" => u.outline, "lessons" => u.lessons,
                        "sections" => sections, "problems" => problems))
    end
    envs = sort!(unique([u.env for u in units]))
    return Dict("julia" => string(VERSION), "generated_by" => "tutor site-data (do not edit; regenerate)",
                "tracks" => Course.TRACKS, "track_requires" => Course.TRACK_REQUIRES, "units" => out,
                "envs" => Dict(e => env_packages(e) for e in envs))
end

"""
The course site data as files: `courses.json` (every course's manifest, the
tracks and the env package versions; no unit content) and one
`course-<id>.json` per course with that course's units. `tutor site-data`
writes them all and `--check` compares them all.
"""
function course_files()
    d = course_data()
    courses = Course.load_courses()
    byid = Dict(u["id"] => u for u in d["units"])
    gen = Dict("julia" => d["julia"], "generated_by" => d["generated_by"])
    index = merge(gen, Dict("tracks" => d["tracks"], "track_requires" => d["track_requires"], "envs" => d["envs"],
        "courses" => Any[Dict("id" => c.id, "title" => c.title, "order" => c.order, "status" => c.status,
                              "summary" => c.summary, "requires" => c.requires, "envs" => c.envs, "units" => c.units,
                              "projects" => c.projects, "guided" => c.guided,
                              "problems" => sum(length(byid[u]["problems"]) for u in c.units; init = 0),
                              "outcomes" => Any[Dict("text" => o.text, "assessed_by" => o.assessed_by,
                                                     "planned" => o.planned) for o in c.outcomes])
                         for c in courses]))
    files = Pair{String,Any}["courses.json" => index]
    for c in courses
        push!(files, "course-$(c.id).json" => merge(gen, Dict("course" => c.id, "units" => Any[byid[u] for u in c.units])))
    end
    return files
end

end # module SiteData
