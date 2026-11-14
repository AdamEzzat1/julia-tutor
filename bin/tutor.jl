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
#   tutor site-data [--check]                 export site/data/ (tutor, courses, course-<id>, guided) for the website
#   tutor course list|verify|record|setup [unit...] [--course=id]  the course: example outputs, grader self-tests, envs
#   tutor courses                              each course: status, units, envs, cross-course prerequisites
#   tutor run <file.jl> [--env=E] [--file]    run code like the sandbox does (fresh process)
#   tutor practice [list | <id> [file.jl]] [--course=id]  show a practice problem, or grade a solution
#   tutor serve [--port=8749] [--allow-origin=URL] [--course=id]  local server for the website sandbox
#   tutor sandbox pull|build|check|measure [course...]  the per-course container images (docs/SANDBOX_IMAGES.md)
#   tutor guided list|show|start|deps|check|quiz|verify ...  guided build projects (docs/GUIDED.md)
#   tutor case list|show|start|check|verify|site ...        scientific case projects (docs/CASES.md)

using JuliaTutor
using JuliaTutor: Checker, Scaffold, Runner, HoleMap, Explain, Lessons, Progress, Fixtures, SiteData,
                  Course, Practice, Server
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

function cmd_site_data(args)
    files = [("tutor.json", SiteData.to_json(SiteData.site_data()));
             [(name, SiteData.to_json(d)) for (name, d) in SiteData.course_files()];
             ("guided.json", SiteData.to_json(JuliaTutor.Guided.site_data()))]
    stale = 0
    # Course data is per course now: a leftover course.json, or a course file
    # for a course that no longer exists, is stale too.
    wanted = Set(first.(files))
    datadir = joinpath(ROOT, "site", "data")
    for f in (isdir(datadir) ? readdir(datadir) : String[])
        (f == "course.json" || (startswith(f, "course-") && endswith(f, ".json"))) && !(f in wanted) || continue
        if hasflag(args, "check")
            println("site/data/$f is obsolete: run `tutor site-data`"); stale += 1
        else
            rm(joinpath(datadir, f)); println("removed site/data/$f")
        end
    end
    for (name, text) in files
        path = joinpath(ROOT, "site", "data", name)
        if hasflag(args, "check")
            same = isfile(path) && read(path, String) == text
            println(same ? "site/data/$name is up to date" : "site/data/$name is stale: run `tutor site-data`")
            stale += !same
        else
            mkpath(dirname(path))
            write(path, text)
            println("wrote site/data/$name ($(length(text)) bytes)")
        end
    end
    # Figures: copies of course/outputs/figures, byte for byte; extra files are stale too.
    figdir = joinpath(ROOT, "site", "assets", "figures")
    figs = SiteData.course_figures()
    want = Set(first.(figs))
    have = isdir(figdir) ? Set("assets/figures/" * replace(relpath(joinpath(r, f), figdir), '\\' => '/')
                               for (r, _, fs) in walkdir(figdir) for f in fs) : Set{String}()
    if hasflag(args, "check")
        bad = [p for (p, b) in figs if !isfile(joinpath(ROOT, "site", p)) || read(joinpath(ROOT, "site", p)) != b]
        extra = setdiff(have, want)
        ok = isempty(bad) && isempty(extra)
        println(ok ? "site/assets/figures is up to date ($(length(figs)) figures)" :
                     "site/assets/figures is stale ($(length(bad)) missing or changed, $(length(extra)) extra): run `tutor site-data`")
        stale += !ok
    else
        rm(figdir; recursive = true, force = true)
        for (p, b) in figs
            dest = joinpath(ROOT, "site", p)
            mkpath(dirname(dest)); write(dest, b)
        end
        println("wrote site/assets/figures ($(length(figs)) figures)")
    end
    return stale == 0 ? 0 : 1
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
            old = isfile(path) ? read(path, String) : ""
            if old != text
                push!(stale, f.name)
                # Show what differs: a STALE line alone is useless when the
                # golden only breaks on another platform (CI).
                a, b = split(old, '\n'), split(text, '\n')
                for i in 1:max(length(a), length(b))
                    la = i <= length(a) ? a[i] : "<none>"
                    lb = i <= length(b) ? b[i] : "<none>"
                    la == lb && continue
                    println("  $(f.name) line $i\n    golden: ", la, "\n    now:    ", lb)
                end
            end
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



# ---- course, sandbox and practice ------------------------------------------------

function cmd_course(args)
    use_sandbox!(args) || return 2
    pos = positional(args)
    isempty(pos) && (println("usage: tutor course <list|verify|record|setup> [unit...]"); return 2)
    sub, rest = pos[1], pos[2:end]
    all_units = Course.load_course()
    courses = Course.load_courses()
    units = course_units(args, courses, all_units)
    units === nothing && return 2
    whole = isempty(rest) && flag(args, "course", "") == ""
    pick(us) = isempty(rest) ? us : filter(u -> u.id in rest || any(r -> startswith(u.id, r * "-"), rest), us)
    if sub == "list"
        byid = Dict(u.id => u for u in units)
        for c in courses
            us = [byid[id] for id in c.units if haskey(byid, id)]
            isempty(us) && continue
            println(c.id, ": ", c.title, " (", c.status, ")")
            for u in us
                println("  ", rpad(u.id, 30), rpad(u.track, 12), rpad(u.status, 8), length(u.problems), " problems  ", u.title)
            end
        end
        return 0
    elseif sub == "record"
        for u in pick(units)
            u.status == "ready" || continue
            println("recording ", u.id, " ...")
            d = Practice.record_unit(u; figures = Course.figures_dir(u))
            mkpath(dirname(Course.outputs_path(u)))
            write(Course.outputs_path(u), Practice.outputs_text(d))
            bad = [k for (k, v) in d["examples"] if !v["ok"]]
            isempty(bad) || println("  note: $(length(bad)) example(s) end in an error (intended ones show an ERROR line)")
        end
        return 0
    elseif sub == "verify"
        # Naming units checks only those (a missing prerequisite may still be
        # being written); a full verify also checks the syllabus as a whole.
        problems = Course.validate_course(whole ? units : pick(units); strict = whole)
        whole && append!(problems, Course.validate_courses(courses, all_units))
        foreach(p -> println("PROBLEM: ", p), problems)
        isempty(problems) || return 1
        for u in pick(units)
            u.status == "ready" || continue
            println("verifying ", u.id, " ...")
            append!(problems, Practice.verify_unit(u; grade_variants = !hasflag(args, "no-grade")))
        end
        foreach(p -> println("PROBLEM: ", p), problems)
        println(isempty(problems) ? "course verified on Julia $(VERSION)" : "$(length(problems)) problem(s)")
        print_peaks()
        return isempty(problems) ? 0 : 1
    elseif sub == "setup"
        # The only networked course step: install and precompile the pinned
        # ecosystem environments into the repo-local depot.
        envs = isempty(rest) ? sort!(unique([u.env for u in units if u.env != "base"])) : rest
        for e in envs
            dir = Course.env_dir(e)
            println("instantiating course/envs/$e ...")
            cmd = `$(Base.julia_cmd()) --startup-file=no --project=$dir -e "using Pkg; Pkg.instantiate(); Pkg.precompile()"`
            run(addenv(cmd, "JULIA_PKG_OFFLINE" => "false"))
            # Load every package once, here, with the network allowed: some
            # fetch lazy artifacts on first load (PythonCall's micromamba_jll and
            # pixi_jll), which would otherwise happen in every sandbox run (a
            # network request, and "Downloading artifact" in recorded outputs).
            pkgs = Practice.env_deps(e)
            isempty(pkgs) && continue
            cmd = `$(Base.julia_cmd()) --startup-file=no --project=$dir -e "using $(join(pkgs, ", "))"`
            # the sandbox's settings (Null CondaPkg backend, no GR window), network on
            run(addenv(cmd, Runner.julia_env()..., "JULIA_PKG_OFFLINE" => "false"))
        end
        return 0
    end
    println("unknown subcommand $sub"); return 2
end

"""
The units `--course=<id>` selects (all units without the flag), or `nothing`
after printing why the course is unknown.
"""
function course_units(args, courses, units)
    id = flag(args, "course", "")
    isempty(id) && return units
    c = findfirst(c -> c.id == id, courses)
    c === nothing && (println("no course $id; courses: ", join([c.id for c in courses], ", ")); return nothing)
    keep = Set(courses[c].units)
    return filter(u -> u.id in keep, units)
end

"""`tutor courses`: each course with its status, units, envs and what it requires."""
function cmd_courses(args)
    units = Course.load_course()
    courses = Course.load_courses()
    byid = Dict(u.id => u for u in units)
    for c in courses
        us = [byid[id] for id in c.units if haskey(byid, id)]
        np = sum(length(u.problems) for u in us; init = 0)
        println(rpad(c.id, 9), rpad(c.title, 22), rpad(c.status, 12), length(us), " units, ", np, " problems")
        isempty(c.status_note) || println("          ", c.status_note)
        lo, hi, _ = Course.time_estimate(c, units)
        println("          about $lo-$hi hours (an estimate from counts, not measured)")
        println("          envs: ", join(c.envs, ", "))
        isempty(c.requires) || println("          requires: ", join(c.requires, ", "))
        cross = sort!(unique([p for u in us for p in u.prerequisites if Course.prereq_course(p) !== nothing]))
        isempty(cross) || println("          builds on: ", join(cross, ", "))
    end
    return 0
end

function cmd_run(args)
    use_sandbox!(args) || return 2
    pos = positional(args)
    length(pos) == 1 || (println("usage: tutor run <file.jl> [--env=base] [--file] [--timeout=60]"); return 2)
    r = Practice.run_code(read(pos[1], String); env = flag(args, "env", "base"),
                          mode = hasflag(args, "file") ? "file" : "repl",
                          timeout = parse(Float64, flag(args, "timeout", "60")))
    print(r.output)
    return r.ok ? 0 : 1
end

function cmd_practice(args)
    use_sandbox!(args) || return 2
    pos = positional(args)
    units = course_units(args, Course.load_courses(), Course.load_course())
    units === nothing && return 2
    if isempty(pos) || pos[1] == "list"
        for u in units, p in u.problems
            println(rpad(p.id, 28), rpad(p.difficulty, 9), rpad(u.id, 26), p.title)
        end
        return 0
    end
    found = Course.find_problem(units, pos[1])
    if found === nothing
        elsewhere = Course.find_problem(Course.load_course(), pos[1])
        elsewhere === nothing ? println("no problem $(pos[1]); see `tutor practice list`") :
            println("problem $(pos[1]) is in course $(Course.course_of(Course.load_courses(), elsewhere[1].id)), " *
                    "not $(flag(args, "course", "")); drop --course or pass that course")
        return 2
    end
    u, p = found
    p.parsons === nothing || length(pos) != 1 || return practice_parsons(u, p, args)
    if length(pos) == 1
        println(p.title, "  [", p.difficulty, ", unit ", u.id, "]\n\n", strip(p.prompt), "\n\nStarter:\n", p.starter)
        println("\nWrite your solution to a file, then: tutor practice $(p.id) <file.jl>")
        return 0
    end
    code = read(pos[2], String)
    r = Practice.grade(p, code; env = u.env)
    print(Practice.format_grade(r))
    passed = r["status"] == "passed"
    if p.bug === nothing
        passed || isempty(p.hints) || println("\nHint: ", p.hints[1])
        return passed ? 0 : 1
    end
    # Find the bug: the measured tests come first; hints fade in with --hints=N.
    tests = Practice.run_bug_tests(p, code; env = u.env)
    print("\n", Practice.format_bug_tests(p, tests))
    nh = min(parse(Int, flag(args, "hints", "0")), length(p.hints))
    for i in 1:nh
        println("\nHint $i: ", p.hints[i])
    end
    if passed && all(t -> t.passed, tests)
        println("\nFixed. The planted line was\n    ", strip(p.bug.replace), "\nand the reference has\n    ",
                strip(p.bug.find), "\n\n", strip(p.bug.misconception))
    elseif nh < length(p.hints)
        println("\nMore help: tutor practice $(p.id) $(pos[2]) --hints=$(nh + 1)")
    end
    return passed && all(t -> t.passed, tests) ? 0 : 1
end

"""
A Parsons problem on the command line: the lines are shown with letters, and
`--order=c,a,f,...` is checked against the measured accepted orderings (no
Julia run). A file can still be graded with `tutor practice <id> file.jl`.
"""
function practice_parsons(u, p, args)
    pool = Course.parsons_pool(p)
    l = Course.parsons_lines(p)
    n = length(l.items)
    shown = Course.parsons_display_order(p.id, pool)          # letter k shows pool[shown[k]]
    letter(k) = string('a' + (k - 1))
    order_arg = flag(args, "order", "")
    if isempty(order_arg)
        println(p.title, "  [", p.difficulty, ", unit ", u.id, "]\n\n", strip(p.prompt), "\n")
        foreach(x -> println("      ", x), l.head)
        println("      ...")
        foreach(x -> println("      ", x), l.tail)
        println("\nLines (use $n of them):")
        for (k, i) in enumerate(shown)
            println("  ", letter(k), "   ", pool[i])
        end
        println("\nAnswer with: tutor practice $(p.id) --order=<your $n letters in order, comma-separated>")
        return 0
    end
    accepted = get(get(Course.load_outputs(u), "parsons", Dict()), p.id, nothing)
    accepted === nothing && (println("no measured orderings for $(p.id) (run `tutor course record $(u.id)`)"); return 2)
    letters = strip.(split(order_arg, ','))
    ks = [length(x) == 1 && 'a' <= x[1] < 'a' + length(pool) ? Int(x[1] - 'a') + 1 : 0 for x in letters]
    order = [k == 0 ? 0 : shown[k] for k in ks]
    fb = Course.parsons_feedback(pool, n, accepted, order)
    if fb.kind == :invalid
        println("Use each letter at most once, from a to ", letter(length(pool)), ".")
    elseif fb.kind == :distractor
        d = p.parsons.distractors[fb.value]
        println("This line does not belong in a working kernel:\n    ", strip(d.line), "\n\n", strip(d.misconception))
    elseif fb.kind == :count
        println("A working order uses exactly ", fb.value, " lines; you gave ", length(order), ".")
    elseif fb.kind == :solved
        println("Works. This order is one of the ", length(accepted), " measured to work:\n")
        println(join([l.head; pool[order]; l.tail], "\n"))
        return 0
    else
        println("The first ", fb.value, " line", fb.value == 1 ? "" : "s", " can start a working order; line ",
                fb.value + 1, " (", strip(pool[order[fb.value+1]]), ") cannot come next.")
        nh = min(parse(Int, flag(args, "hints", "0")), length(p.hints))
        for i in 1:nh
            println("\nHint $i: ", p.hints[i])
        end
        nh < length(p.hints) && println("\nMore help: add --hints=$(nh + 1)")
    end
    return 1
end

function cmd_serve(args)
    port = parse(Int, flag(args, "port", string(Server.DEFAULT_PORT)))
    extra = [String(split(a, "=", limit = 2)[2]) for a in args if startswith(a, "--allow-origin=")]
    return Server.serve(; port, origins = vcat(Server.DEFAULT_ORIGINS, extra),
                        site = flag(args, "site", "https://adamezzat1.github.io/julia-tutor/"),
                        token_file = flag(args, "token-file", Server.TOKEN_FILE),
                        sandbox = Symbol(flag(args, "sandbox", "docker")),
                        course = flag(args, "course", ""))
end

"""The images a command needs: those of `--course=<id>`, or all of them."""
function needed_images(args)
    c = flag(args, "course", "")
    return isempty(c) ? Runner.images() : unique(["base", Runner.course_image(c)])
end

# `--sandbox=docker` on run/practice/course: the same container `tutor serve` uses
# (checking the course inside it). The default for those is a plain process.
function use_sandbox!(args)
    s = flag(args, "sandbox", "none")
    s in ("none", "docker") || (println("--sandbox must be docker or none"); return false)
    if s == "docker"
        why = Runner.sandbox_problem(needed_images(args))
        why === nothing || (println(why); return false)
    end
    Runner.SANDBOX[] = Symbol(s)
    return true
end

gib(b) = string(round(b / 2^30; digits = 2), " GiB")
peak_source(s) = s == "cgroup" ? "cgroup memory.peak (all processes, page cache included)" :
                                   "Julia's peak RSS (kernel has no memory.peak; no page cache, child processes not counted)"

"""The memory peaks the contained runs of this process reached, per environment (markdown)."""
function print_peaks(what = "tutor course verify")
    (Runner.SANDBOX[] === :docker && !isempty(Runner.MEMORY_PEAKS)) || return
    io = IOBuffer()
    println(io, "\n### Memory peaks per environment ($what, largest container)\n")
    println(io, "| environment | image | memory limit | peak | measured as |")
    println(io, "|---|---|---|---|---|")
    for (e, (b, src)) in sort!(collect(Runner.MEMORY_PEAKS))
        img = Runner.env_image(e)
        println(io, "| $e | $img | $(Runner.image_memory(img)) | $(gib(b)) | $(peak_source(src)) |")
    end
    report(String(take!(io)))
end

"""Print a markdown report, and add it to the CI job summary when there is one."""
function report(s::AbstractString)
    print(s)
    f = get(ENV, "GITHUB_STEP_SUMMARY", "")
    isempty(f) || open(io -> print(io, s), f, "a")
end

"""Images named on the command line by course (core = base), or all of them."""
function images_arg(pos)
    isempty(pos) && return (Runner.images(), nothing)
    courses = [c.id for c in Course.load_courses()]
    bad = filter(c -> !(c in courses), pos)
    isempty(bad) || return (String[], "no course $(join(bad, ", ")); courses: $(join(courses, ", "))")
    return (unique(Runner.course_image.(pos)), nothing)
end

const SANDBOX_USAGE = """
    usage: tutor sandbox <command> [course...]   (no course: every image; core uses the base image)
      pull <course...>      fetch the published images (sandbox/images.toml, by digest)
      build [course...]     build the images from this checkout (offline or audited setups)
      check [course...]     self-test the images: network, read-only root, every environment loads
      measure [course...]   image sizes, cold-start times and memory peaks (markdown)
      publish [--push]      CI: pull each image for these inputs from the registry, else build (and push) it
      digests [--check]     CI: print sandbox/images.toml for the local images, or check the committed one"""

"""
Code for `tutor sandbox check`: in the environment it runs in, start a second
Julia that presents the most basic CPU of its architecture (`-C generic`) and
list every package whose precompiled cache that CPU would reject. A cache
compiled only for the build machine's CPU is rejected there on any machine, so
the check does not depend on which CPU CI happens to get. Prints `:portable`
when every cache loads.
"""
function portable_code(pkgs)
    return """
    let jl = joinpath(Sys.BINDIR, "julia"), pk = $(repr(String.(pkgs)))
        script = "for p in ARGS; Base.isprecompiled(Base.identify_package(p)) || println(p); end"
        out = read(`\$jl --startup-file=no -C generic --project=\$(Base.active_project()) -e \$script \$pk`, String)
        isempty(out) ? :portable : Symbol("rejected: ", join(split(out), ", "))
    end
    """
end

function cmd_sandbox(args)
    pos = positional(args)
    sub = isempty(pos) ? "" : pos[1]
    imgs, bad = images_arg(pos[2:end])
    bad === nothing || (println(bad); return 2)
    nodocker() = Sys.which("docker") === nothing && (println("Docker is not installed (no `docker` on PATH)."); true)
    if sub == "build"
        nodocker() && return 1
        for img in imgs
            println("building $(Runner.image_name(img)) (downloads julia:$(VERSION) and the course packages the first time) ...")
            Runner.build_sandbox(img)
        end
        return 0
    elseif sub == "pull"
        length(pos) > 1 || (println("usage: tutor sandbox pull <course...>  (courses: ",
                                    join([c.id for c in Course.load_courses()], ", "), ")"); return 2)
        nodocker() && return 1
        for img in unique(["base"; imgs])
            println("pulling $(Runner.image_course(img)) ($(Runner.image_name(img))) ...")
            t = @elapsed why = Runner.pull_image(img)
            why === nothing || (println(why); return 1)
            println("  ready in $(round(t; digits = 1)) s")
        end
        return 0
    elseif sub == "check"
        why = Runner.sandbox_problem(unique(["base"; imgs]))
        why === nothing || (println(why); return 1)
        Runner.SANDBOX[] = :docker
        checks = [("runs Julia", "VERSION", r"1\.10\.13", "base"),
                  ("no network", "using Sockets; try connect(\"1.1.1.1\", 53); \"connected\" catch e; \"blocked\" end", r"blocked", "base"),
                  ("read-only system", "try touch(\"/usr/x\"); \"wrote\" catch e; \"blocked\" end", r"blocked", "base")]
        "science" in imgs &&
            push!(checks, ("ecosystem packages", "using DataFrames; nrow(DataFrame(a = 1:3))", r"^3$"m, "data"))
        # Every environment loads, as the run-time user, printing nothing else:
        # no "Precompiling" (nothing may compile at run time) and no "WARNING:
        # using X.f in module Main conflicts" (a child helper shadowing an export).
        for img in imgs, e in Runner.image_envs()[img]
            pkgs = Practice.env_deps(e)
            (e == "data" || isempty(pkgs)) && continue
            push!(checks, ("env $e loads ($img image)", "using " * join(pkgs, ", ") * "; :loaded", r"\A:loaded\s*\z", e))
        end
        # The caches must load on CPUs other than the build machine's (the
        # images are built on one CI runner and run on any learner's machine).
        for img in imgs, e in Runner.image_envs()[img]
            pkgs = Practice.env_deps(e)
            isempty(pkgs) && continue
            push!(checks, ("env $e caches load on a baseline CPU ($img image)", portable_code(pkgs), r"\A:portable\s*\z", e))
        end
        bad = 0
        for (what, code, want, env) in checks
            r = Practice.run_code(code; env, timeout = 240)
            ok = occursin(want, r.output)
            println(ok ? "  ok    " : "  FAIL  ", what, ok ? "" : ": " * strip(r.output))
            bad += !ok
        end
        return bad == 0 ? 0 : 1
    elseif sub == "measure"
        why = Runner.sandbox_problem(unique(["base"; imgs]))
        why === nothing || (println(why); return 1)
        Runner.SANDBOX[] = :docker
        io = IOBuffer()
        println(io, "\n### Sandbox images (tutor sandbox measure)\n")
        println(io, "| image | size on disk (uncompressed) | layers a pull downloads (compressed) |")
        println(io, "|---|---|---|")
        for img in imgs
            s, d = Runner.image_sizes(img)
            println(io, "| $img | $(s === nothing ? "?" : gib(s)) | $(d === nothing ? "not published" : gib(d)) |")
        end
        # Every run is a fresh container, so each one is a cold start of the
        # container and of Julia; the first after a pull also reads the image
        # from disk. Three runs each, all shown.
        println(io, "\n| image | environment | what runs | seconds (3 fresh containers) | memory peak |")
        println(io, "|---|---|---|---|---|")
        for img in imgs, e in (img == "base" ? ["base"] : Runner.image_envs()[img])
            pkgs = Practice.env_deps(e)
            code = isempty(pkgs) || e == "base" ? "1 + 1" : "using " * join(pkgs, ", ") * "; :loaded"
            empty!(Runner.MEMORY_PEAKS)
            ts = [round(Practice.run_code(code; env = e, timeout = 600).seconds; digits = 1) for _ in 1:3]
            peak = get(Runner.MEMORY_PEAKS, e, nothing)
            println(io, "| $img | $e | `$(length(code) > 40 ? code[1:37] * "..." : code)` | $(join(ts, ", ")) | ",
                    peak === nothing ? "?" : "$(gib(peak[1])) ($(peak_source(peak[2])))", " |")
        end
        report(String(take!(io)))
        return 0
    elseif sub == "publish"
        nodocker() && return 1
        digests = Dict{String,String}()
        failed = String[]
        # Every image is tried even when one fails, so a single run reports
        # (and, on GHCR, creates the package for) each one that needs attention.
        for img in Runner.images()
            d = try
                Runner.publish_image(img; push = hasflag(args, "push"))
            catch e
                e isa InterruptException && rethrow()
                println("  $img: FAILED: ", sprint(showerror, e))
                push!(failed, img)
                nothing
            end
            d === nothing || (digests[img] = d)
        end
        print(Runner.images_toml(digests))
        isempty(failed) && return 0
        println("\nFailed: ", join(failed, ", "), ". On GHCR, a push the registry denies usually means the ",
                "package's \"Manage Actions access\" lacks this repository with the Write role.")
        return 1
    elseif sub == "digests"
        digests = Dict{String,String}()
        for img in Runner.images()
            d = Runner.local_digest(img)
            d === nothing || (digests[img] = d)
        end
        want = Runner.images_toml(digests)
        hasflag(args, "check") || (print(want); return 0)
        have = isfile(Runner.IMAGES_FILE) ? replace(read(Runner.IMAGES_FILE, String), "\r\n" => "\n") : ""
        have == want && (println("sandbox/images.toml matches the published images"); return 0)
        println("sandbox/images.toml does not match the images for this checkout. Commit this as sandbox/images.toml:\n")
        print(want)
        return 1
    end
    println(SANDBOX_USAGE); return 2
end

# ---- guided build projects (docs/GUIDED.md) -------------------------------------------

using JuliaTutor: Guided

const GUIDED_USAGE = """
usage: tutor guided list
       tutor guided show <project> [milestone]
       tutor guided start <project> <dir>
       tutor guided deps <dir>
       tutor guided check <dir> [milestone] [--hints=N] [--sandbox=docker|none] [--no-record] [--state=path]
       tutor guided quiz <project> <milestone>
       tutor guided verify [project...] [--sandbox=docker|none]"""

"""The project a student folder belongs to (written by `guided start` into .guided)."""
function guided_of(dir)
    f = joinpath(dir, ".guided")
    isfile(f) || return nothing
    return Guided.load_guided(strip(read(f, String)))
end

# Guided checks default to the container; a plain process only where asked and the env loads on the host.
function guided_sandbox!(args, p)
    s = flag(args, "sandbox", "docker")
    if s == "none" && p !== nothing && !Guided.host_ok(p)
        println("--sandbox=none: the $(p.env) environment loads only in the container on this kind of host (see CLAUDE.md, Known gaps)")
        return false
    end
    return use_sandbox!(vcat(filter(a -> !startswith(a, "--sandbox="), args), "--sandbox=$s"))
end

function cmd_guided(args)
    pos = positional(args)
    sub = isempty(pos) ? "" : pos[1]
    if sub == "list"
        for p in Guided.load_all()
            println(rpad(p.name, 12), rpad(p.status, 9), rpad(p.env, 10), rpad("$(length(p.milestones)) milestones", 15),
                    Guided.host_ok(p) ? "host or container  " : "container only     ", p.title)
        end
        return 0
    elseif sub == "show" && length(pos) in (2, 3)
        p = Guided.load_guided(pos[2])
        m = length(pos) == 3 ? parse(Int, pos[3]) : 0
        print(Guided.show_milestone(p, m))
        return 0
    elseif sub == "start" && length(pos) == 3
        p = Guided.load_guided(pos[2]); dir = pos[3]
        isdir(dir) && !isempty(readdir(dir)) && (println("refusing: $dir exists and is not empty"); return 1)
        files = Guided.start_files(p)
        files[".guided"] = p.name * "\n"
        for rel in sort!(collect(keys(files)))
            mkpath(dirname(joinpath(dir, rel))); write(joinpath(dir, rel), files[rel])
        end
        println("Created $dir (", join(sort!(collect(keys(files))), ", "), "). Next: tutor guided show $(p.name) 0")
        return 0
    elseif sub == "deps" && length(pos) == 2
        dir = pos[2]; p = guided_of(dir)
        p === nothing && (println("$dir was not created by `tutor guided start`"); return 1)
        f = joinpath(dir, "Project.toml")
        isfile(f) || (println("no $f yet: milestone 0 creates it with Pkg.generate"); return 1)
        write(f, Guided.with_deps(read(f, String), p.env))
        println("wrote [deps] for the $(p.env) environment (", join(Practice.env_deps(p.env), ", "), ") and Test as a test dependency into $f")
        return 0
    elseif sub == "check" && length(pos) in (2, 3)
        dir = pos[2]; p = guided_of(dir)
        p === nothing && (println("$dir was not created by `tutor guided start`"); return 1)
        guided_sandbox!(args, p) || return 2
        state_path = flag(args, "state", Guided.DEFAULT_STATE)
        state = Guided.load_state(state_path)
        key = Guided.statekey(p, dir)
        m = length(pos) == 3 ? parse(Int, pos[3]) : Guided.next_milestone(p, state, key)
        hints = parse(Int, flag(args, "hints", "0"))
        r, findings = Guided.check(p, dir, m; levels = Guided.levels_from(state, key), hints)
        print(Guided.format_check(r, findings; hints))
        if !hasflag(args, "no-record")
            Guided.save_state(state_path, Guided.record!(state, key, r, p))
        end
        if r["status"] == "passed"
            nxt = findfirst(x -> x.id > m, p.milestones)
            println(nxt === nothing ? "\nAll milestones done." :
                    "\nNext: tutor guided show $(p.name) $(p.milestones[nxt].id)" *
                    (isempty(Guided.milestone(p, m).questions) ? "" : "  (and the questions: tutor guided quiz $(p.name) $m)"))
        end
        return r["status"] == "passed" ? 0 : 1
    elseif sub == "quiz" && length(pos) == 3
        p = Guided.load_guided(pos[2])
        right, n = Guided.quiz(p, parse(Int, pos[3]))
        println("\n$right of $n right on the first try.")
        return 0
    elseif sub == "verify"
        names = length(pos) > 1 ? pos[2:end] : [p.name for p in Guided.load_all()]
        guided_sandbox!(args, nothing) || return 2
        bad = 0
        for n in names
            p = Guided.load_guided(n)
            println(n, " (", p.status, ")")
            problems = Guided.verify_project(p)
            foreach(x -> println("  PROBLEM: ", replace(x, "\n" => "\n    ")), problems)
            bad += length(problems)
        end
        println(bad == 0 ? "guided projects verified" : "$bad problem(s)")
        print_peaks("tutor guided verify")
        return bad == 0 ? 0 : 1
    end
    println(GUIDED_USAGE); return 2
end

# ---- scientific case projects (docs/CASES.md) -----------------------------------------

using JuliaTutor: Cases

const CASE_USAGE = """
usage: tutor case list
       tutor case show <case> [--rubric]
       tutor case start <case> <dir>
       tutor case estimate <dir> <id> <value> "<how you got it>"
       tutor case check <dir> <milestone> [--sandbox=docker|none] [--no-record]
       tutor case verify [case...] [--sandbox=docker|none]
       tutor case site [case...] [--check]"""

function cmd_case(args)
    pos = positional(args)
    sub = isempty(pos) ? "" : pos[1]
    if sub == "list"
        for n in Cases.case_names()
            c = Cases.load_case(n)
            println(rpad(c.name, 12), rpad(c.course, 10), rpad("$(length(c.milestones)) milestones", 15),
                    rpad("pilot: " * get(c.pilot, "status", "?"), 18), c.title)
        end
        return 0
    elseif sub == "show" && length(pos) == 2
        c = Cases.load_case(pos[2])
        println("# ", c.title, "\n")
        print(Cases.brief_markdown(c; rubric = hasflag(args, "rubric")))
        return 0
    elseif sub == "start" && length(pos) == 3
        c = Cases.load_case(pos[2]); dir = pos[3]
        isdir(dir) && !isempty(readdir(dir)) && (println("refusing: $dir exists and is not empty"); return 1)
        files = Cases.start_files(c)
        for rel in sort!(collect(keys(files)))
            mkpath(dirname(joinpath(dir, rel))); write(joinpath(dir, rel), files[rel])
        end
        println("Created $dir: the $(c.project) package with every hole open, study/study.jl, report.qmd and BRIEF.md.")
        println("Next: read BRIEF.md, then tutor case check $dir 2")
        return 0
    elseif sub == "check" && length(pos) == 3
        dir = pos[2]; c = Cases.case_of(dir)
        c === nothing && (println("$dir was not created by `tutor case start` or `tutor start` for a case project"); return 1)
        use_sandbox!(vcat(filter(a -> !startswith(a, "--sandbox="), args), "--sandbox=$(flag(args, "sandbox", "docker"))")) || return 2
        passed, text = Cases.check(c, dir, parse(Int, pos[3]); record = !hasflag(args, "no-record"))
        print(text)
        return passed ? 0 : 1
    elseif sub == "estimate" && length(pos) == 5
        dir = pos[2]; c = Cases.case_of(dir)
        c === nothing && (println("$dir was not created by `tutor case start` or `tutor start` for a case project"); return 1)
        ok, msg = Cases.commit_estimate(c, dir, pos[3], pos[4], pos[5])
        println(ok ? msg : "refused: " * msg)
        return ok ? 0 : 1
    elseif sub == "verify"
        names = length(pos) > 1 ? pos[2:end] : Cases.case_names()
        use_sandbox!(vcat(filter(a -> !startswith(a, "--sandbox="), args), "--sandbox=$(flag(args, "sandbox", "docker"))")) || return 2
        bad = 0
        for n in names
            println(n)
            problems = Cases.verify_case(Cases.load_case(n))
            foreach(x -> println("  PROBLEM: ", replace(x, "\n" => "\n    ")), problems)
            bad += length(problems)
        end
        println(bad == 0 ? "case projects verified" : "$bad problem(s)")
        print_peaks("tutor case verify")
        return bad == 0 ? 0 : 1
    elseif sub == "site"
        names = length(pos) > 1 ? pos[2:end] : Cases.case_names()
        stale = 0
        for n in names
            c = Cases.load_case(n)
            path = Cases.site_page_path(c); want = Cases.site_page(c)
            if hasflag(args, "check")
                have = isfile(path) ? replace(read(path, String), "\r\n" => "\n") : ""
                have == want ? println("$(relpath(path, JuliaTutor.ROOT)) is up to date") :
                               (println("$(relpath(path, JuliaTutor.ROOT)) is stale: run tutor case site $n"); stale += 1)
            else
                write(path, want); println("wrote $(relpath(path, JuliaTutor.ROOT))")
            end
        end
        return stale == 0 ? 0 : 1
    end
    println(CASE_USAGE); return 2
end

const COMMANDS = Dict("guided" => cmd_guided, "case" => cmd_case, "check" => cmd_check, "scaffold" => cmd_scaffold, "start" => cmd_start,
                      "test" => cmd_test, "explain" => cmd_explain, "holemap" => cmd_holemap,
                      "baseline" => cmd_baseline, "lessons" => cmd_lessons, "lesson" => cmd_lesson,
                      "rules" => cmd_rules, "progress" => cmd_progress, "fixtures" => cmd_fixtures,
                      "site-data" => cmd_site_data, "course" => cmd_course, "courses" => cmd_courses, "run" => cmd_run,
                      "practice" => cmd_practice, "serve" => cmd_serve, "sandbox" => cmd_sandbox)

function main(args)
    JuliaTutor.check_julia_version()
    if isempty(args) || !haskey(COMMANDS, args[1])
        println("usage: tutor <", join(sort!(collect(keys(COMMANDS))), "|"), "> ...  (see bin/tutor.jl)")
        return 2
    end
    return COMMANDS[args[1]](args[2:end])
end

exit(main(ARGS))
