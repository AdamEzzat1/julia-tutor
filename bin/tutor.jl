# Command-line entry point. Run through the `tutor` / `tutor.ps1` wrappers, which
# pin the Julia release, the depot and the thread counts.
#
#   tutor check <paths...> [--hints=N]        static checker (exit 1 on WARN/ERROR)
#   tutor scaffold <project> [--check]        generate (or diff) starter stages
#   tutor start <project> <stage> <dir>       copy a starter stage to work on
#   tutor test <dir>                          run a project's tests, per testset
#   tutor explain <project> <dir> [--hints=N] [--no-measure] [--jet] [--no-record] [--state=path]
#   tutor progress [--state=path]              learner model: KCs, hole attempts, reviews due
#   tutor fixtures <project> [--check]        explain on buggy fixtures vs golden outputs
#   tutor holemap <project> [--check]         measure test->hole map + mutation tests
#   tutor baseline <project> [--check]        measure the reference (explain compares)
#   tutor lessons verify                      run every lesson snippet, check keys
#   tutor lesson <id> [--state=path]          take a lesson interactively
#   tutor rules                               list rules with FP risk and hints

using JuliaTutor
using JuliaTutor: Checker, Scaffold, Runner, HoleMap, Explain, Lessons, Progress, Fixtures
using TOML, Dates

const ROOT = JuliaTutor.ROOT

flag(args, name, default) = (i = findfirst(a -> startswith(a, "--$name="), args);
                             i === nothing ? default : String(split(args[i], "=", limit = 2)[2]))   # String: callers dispatch on it
hasflag(args, name) = "--$name" in args
positional(args) = filter(a -> !startswith(a, "--"), args)

project(name) = Scaffold.load_project(joinpath(ROOT, "projects", name))

function cmd_check(args)
    fs = Checker.check_paths(positional(args))
    print(Checker.format_findings(fs; hints = parse(Int, flag(args, "hints", "0"))))
    return Checker.exit_code(fs)
end

function cmd_scaffold(args)
    p = project(positional(args)[1])
    if hasflag(args, "check")
        problems = Scaffold.check_starter(p)
        foreach(println, problems)
        isempty(problems) && println("starter for $(p.name) is up to date")
        return isempty(problems) ? 0 : 1
    end
    Scaffold.write_starter(p)
    println("wrote ", join(["projects/$(p.name)/starter/stage$s" for s in p.stages], ", "))
    return 0
end

function cmd_start(args)
    name, stage, dir = positional(args)
    p = project(name)
    isdir(dir) && !isempty(readdir(dir)) && (println("refusing: $dir exists and is not empty"); return 1)
    files = Scaffold.starter_files(p, parse(Int, stage))
    for rel in sort!(collect(keys(files)))
        mkpath(dirname(joinpath(dir, rel)))
        write(joinpath(dir, rel), files[rel])
    end
    println("Created $dir. Next: tutor explain $name $dir")
    return 0
end

function cmd_test(args)
    rep = Runner.run_tests(positional(args)[1])
    for t in rep.testsets
        println(Runner.ok(t) ? "PASS " : "FAIL ", t.name, "  ($(t.passed) passed, $(t.failed) failed, $(t.errored) errored)")
        Runner.ok(t) || foreach(m -> println("     ", m), t.messages)
    end
    isempty(rep.crash) || println("CRASH: ", rep.crash)
    return all(Runner.ok, rep.testsets) && isempty(rep.crash) ? 0 : 1
end

const DEFAULT_STATE = joinpath(".tutor", "state.toml")

function cmd_explain(args)
    name, dir = positional(args)
    r = Explain.explain(project(name), dir; hints = parse(Int, flag(args, "hints", "1")),
                        run_measurements = !hasflag(args, "no-measure"), jet = hasflag(args, "jet"))
    print(r.text)
    # Learner model: applied here, not in explain, so explain's text stays a pure
    # function of the student's code (goldens compare it).
    if !hasflag(args, "no-record")
        path = flag(args, "state", DEFAULT_STATE)
        state = Progress.load_state(path)
        lines = Progress.apply_observations!(state, r.observations)
        Progress.save_state(path, state)
        println("\nLearner model ($path):")
        isempty(lines) && println("  no unambiguous evidence about any implemented hole in this run")
        foreach(l -> println("  ", l), lines)
    end
    println("\nLatency (wall clock, this machine; not part of the deterministic report):")
    for (label, s) in r.timings
        println("  ", rpad(label, 26), round(s; digits = 1), " s")
    end
    return r.exitcode
end

function cmd_progress(args)
    path = flag(args, "state", DEFAULT_STATE)
    print(Progress.format_progress(Progress.load_state(path); today = Dates.today()))
    return 0
end

function cmd_fixtures(args)
    p = project(positional(args)[1])
    fx = Fixtures.load_fixtures(p)
    problems = Fixtures.validate_fixtures(p, fx)
    isempty(problems) || (foreach(x -> println("PROBLEM: ", x), problems); return 1)
    println("running explain on $(length(fx)) fixtures for $(p.name)...")
    results = Fixtures.compute_goldens(p, fx)
    stale = String[]
    for f in fx
        text, probs = results[f.name]
        append!(problems, probs)
        path = Fixtures.golden_path(p, f)
        if hasflag(args, "check")
            (isfile(path) && read(path, String) == text) || push!(stale, f.name)
        else
            mkpath(dirname(path))
            write(path, text)
        end
    end
    foreach(x -> println("PROBLEM: ", x), problems)
    if hasflag(args, "check")
        foreach(n -> println("STALE: fixtures/$n.golden.txt differs (review, then `tutor fixtures $(p.name)`)"), stale)
        isempty(stale) && println("all $(length(fx)) golden outputs are up to date")
    else
        println("wrote $(length(fx)) golden outputs to projects/$(p.name)/fixtures/")
    end
    return isempty(problems) && isempty(stale) ? 0 : 1
end

function cmd_holemap(args)
    p = project(positional(args)[1])
    println("measuring test->hole map for $(p.name) (one fresh process per variant)...")
    d = HoleMap.compute_holemap(p)
    text = HoleMap.holemap_toml(d)
    path = joinpath(p.dir, "holemap.toml")
    foreach(x -> println("PROBLEM: ", x), d["problems"])
    if hasflag(args, "check")
        same = isfile(path) && read(path, String) == text
        println(same ? "holemap.toml is up to date" : "holemap.toml is stale: run `tutor holemap $(p.name)`")
        return same && isempty(d["problems"]) ? 0 : 1
    end
    write(path, text)
    println("wrote ", path)
    return isempty(d["problems"]) ? 0 : 1
end

function cmd_baseline(args)
    p = project(positional(args)[1])
    m = Explain.measure(p, Scaffold.reference_dir(p); jet = true)   # baseline records JET too
    io = IOBuffer()
    println(io, "# Generated by `tutor baseline $(p.name)` from the reference on Julia $(VERSION). Do not edit.")
    TOML.print(io, m; sorted = true)
    text = String(take!(io))
    path = joinpath(p.dir, "measure_baseline.toml")
    if hasflag(args, "check")
        same = isfile(path) && read(path, String) == text
        println(same ? "measure_baseline.toml is up to date" : "measure_baseline.toml differs:\n" * text)
        return same ? 0 : 1
    end
    write(path, text)
    print(text)
    return 0
end

function cmd_lessons(args)
    positional(args) == ["verify"] || (println("usage: tutor lessons verify"); return 2)
    problems = Lessons.verify_lessons(Lessons.load_lessons())
    foreach(p -> println("PROBLEM: ", p), problems)
    println(isempty(problems) ? "all lesson answer keys verified on Julia $(VERSION)" : "$(length(problems)) problem(s)")
    return isempty(problems) ? 0 : 1
end

function cmd_lesson(args)
    id = positional(args)[1]
    lessons = Lessons.load_lessons()
    i = findfirst(l -> l.id == id || startswith(l.id, id * "-"), lessons)
    i === nothing && (println("no lesson $id; have: ", join([l.id for l in lessons], ", ")); return 2)
    Lessons.run_lesson(lessons[i]; state_path = flag(args, "state", joinpath(".tutor", "state.toml")),
                       all_lessons = lessons)
    return 0
end

function cmd_rules(_)
    for r in Checker.RULES
        m = Checker.meta(r)
        println(m.id, " ", m.name, " [", m.severity, ", kc=", m.kc, "]")
        println("  false-positive risk: ", m.fp_risk)
        println("  confirmed by: ", m.measured_by)
        for (i, h) in enumerate(m.hints)
            println("  hint $i: ", h)
        end
    end
    return 0
end

const COMMANDS = Dict("check" => cmd_check, "scaffold" => cmd_scaffold, "start" => cmd_start,
                      "test" => cmd_test, "explain" => cmd_explain, "holemap" => cmd_holemap,
                      "baseline" => cmd_baseline, "lessons" => cmd_lessons, "lesson" => cmd_lesson,
                      "rules" => cmd_rules, "progress" => cmd_progress, "fixtures" => cmd_fixtures)

function main(args)
    JuliaTutor.check_julia_version()
    if isempty(args) || !haskey(COMMANDS, args[1])
        println("usage: tutor <", join(sort!(collect(keys(COMMANDS))), "|"), "> ...  (see bin/tutor.jl)")
        return 2
    end
    return COMMANDS[args[1]](args[2:end])
end

exit(main(ARGS))
