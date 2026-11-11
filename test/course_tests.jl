# Course, grader and sandbox-server tests (included from runtests.jl).
using JuliaTutor: JSON, Course, Practice, Server, Runner, SiteData
using Base64

@testset "JSON reader and writer" begin
    v = JSON.parse_json("""{"a": [1, 2.5, true, null, "x\\n\\u00e9\\ud83d\\ude00"], "b": {}}""")
    @test v["a"][1] === 1 && v["a"][2] === 2.5 && v["a"][3] === true && v["a"][4] === nothing
    @test v["a"][5] == "x\né😀"
    @test v["b"] == Dict{String,Any}()
    for bad in ["", "{", "[1,]", "{\"a\" 1}", "01", "1.", "\"\\x\"", "nul", "[1] 2", "\"a\nb\"", "-"]
        @test_throws JSON.JSONError JSON.parse_json(bad)
    end
    @test_throws JSON.JSONError JSON.parse_json("["^100 * "]"^100)        # depth limit
    d = Dict("z" => 1, "a" => Any[1.5, nothing, "q\""], "m" => Dict("k" => false))
    @test JSON.parse_json(JSON.to_json(d)) == d
    @test JSON.parse_json(JSON.to_json_compact(d)) == d
    @test JSON.to_json_compact(Dict("b" => 1, "a" => 2)) == "{\"a\":2,\"b\":1}"   # sorted keys
end

@testset "course structure" begin
    units = Course.load_course()
    @test Course.validate_course(units) == String[]
    @test issorted([u.id for u in units])
    @test Course.example_key("x\r\n") == Course.example_key("x")   # line endings never change a key
    # the sciml track assumes the whole earlier course
    # (a planned unit: only its outline is checked, so it shares nothing with `eco`)
    re(v; id = v.id, track = v.track, pre = v.prerequisites) = Course.Unit(id, v.title, track, v.env, "planned",
        v.summary, v.kcs, pre, ["an outline"], String[], Course.Section[], Course.Problem[])
    eco = units[findlast(v -> v.track == "ecosystem", units)]
    sml = re(eco; id = "99-x", track = "sciml", pre = [eco.id])
    @test Course.validate_course([units; sml]) == String[]
    @test any(contains("must name the earlier units"), Course.validate_course([units; re(sml; pre = String[])]))
    @test any(contains("must come before it"), Course.validate_course([sml; units]; strict = false))
    @test Course.example_key("x", "file") != Course.example_key("x")
    for u in units
        @test u.id == splitext(basename(Course.outputs_path(u)))[1]
        u.status == "ready" && @test isfile(Course.outputs_path(u))
    end
end

@testset "courses: manifests and cross-course prerequisites" begin
    units = Course.load_course()
    courses = Course.load_courses()
    @test Course.validate_courses(courses, units) == String[]
    @test [c.id for c in courses] == ["core", "science", "scicomp", "sciml"]
    # every unit in exactly one course; the split keeps the syllabus order
    @test sort!(vcat([c.units for c in courses]...)) == sort!([u.id for u in units])
    @test vcat([c.units for c in courses]...) == [u.id for u in units]
    @test Course.prereq_unit("scicomp/35-stiffness") == "35-stiffness" && Course.prereq_unit("35-stiffness") == "35-stiffness"
    @test Course.prereq_course("scicomp/35-stiffness") == "scicomp" && Course.prereq_course("35-stiffness") === nothing
    @test Course.course_of(courses, "46-sindy") == "sciml"

    # one change at a time to the real data, each must be reported
    C(c; units = c.units, requires = c.requires, envs = c.envs, guided = c.guided, outcomes = c.outcomes) =
        Course.CourseInfo(c.id, c.title, c.order, c.status, c.summary, requires, envs, units, c.projects, guided, outcomes)
    swap(i, c) = [j == i ? c : courses[j] for j in eachindex(courses)]
    U(u; pre = u.prerequisites) = Course.Unit(u.id, u.title, u.track, u.env, u.status, u.summary, u.kcs, pre,
                                               u.outline, u.lessons, u.sections, u.problems)
    setpre(id, pre) = [u.id == id ? U(u; pre) : u for u in units]
    has(msg, cs = courses, us = units) = any(contains(msg), Course.validate_courses(cs, us))
    core, sci, scc, sml = courses
    @test has("belongs to no course", swap(1, C(core; units = core.units[1:end-1])))
    @test has("more than one course", swap(2, C(sci; units = ["20-stdlib-tour"; sci.units])))
    @test has("is not in course scicomp", courses, setpre("35-stiffness", ["24-differential-equations"]))   # cross-course, bare
    @test has("in the same course", courses, setpre("35-stiffness", ["scicomp/34-pde-discretization"]))
    @test has("unknown course", courses, setpre("35-stiffness", ["physics/34-pde-discretization"]))
    @test has("no unit 34-pde-discretization in course science", courses, setpre("35-stiffness", ["science/34-pde-discretization"]))
    @test has("does not require", swap(3, C(scc; requires = ["core"])))
    @test has("which comes later", swap(1, C(core; requires = ["sciml"])))
    @test has("envs must be exactly", swap(4, C(sml; envs = ["base", "sciml", "plots"])))    # an image with an env it never uses
    @test has("envs must be exactly", swap(3, C(scc; envs = ["base", "scicomp"])))          # missing mtk
    @test has("guided project epidemic belongs to 0 courses",
              swap(2, C(sci; guided = filter(!=("epidemic"), sci.guided), envs = sci.envs)))
    @test has("4 to 8 outcomes", swap(1, C(core; outcomes = core.outcomes[1:3])))
    @test has("is not a unit or project of this course",
              swap(1, C(core; outcomes = [Course.Outcome("x", ["46-sindy"], String[]); core.outcomes[2:end]])))
    @test has("nothing assesses it",
              swap(1, C(core; outcomes = [Course.Outcome("x", String[], String[]); core.outcomes[2:end]])))
    # a prerequisite cycle, even one the file order would not show
    cyc = setpre("01-first-steps", ["03-strings"])
    @test Course.prereq_cycle(cyc) == ["01-first-steps", "03-strings", "01-first-steps"]
    @test has("prerequisite cycle", courses, cyc)
    @test Course.prereq_cycle(units) === nothing
    # the real dependencies: scicomp no longer reaches probabilistic programming (unit 37 states the fact itself)
    @test !any(id -> "27-probabilistic-programming" in Course.prereq_closure(units, id), scc.units)
    @test "35-stiffness" in Course.prereq_closure(units, "36-daes")
end

@testset "courses: learner state from before the split survives" begin
    # State written before the split (test/fixtures/*_v1.toml) loads as it is
    # and every entry maps to exactly one course: no key had to be renamed.
    dir = joinpath(@__DIR__, "fixtures")
    state = JuliaTutor.Progress.load_state(joinpath(dir, "state_v1.toml"))
    guided = JuliaTutor.Guided.load_state(joinpath(dir, "guided_v1.toml"))
    report = JuliaTutor.Progress.format_progress(state; today = Dates.Date(2026, 11, 12))
    @test occursin("symdiff/product_rule", report) && occursin("L02-concrete-types/abstract-field", report)
    by, unmapped = Course.state_by_course(state, guided, Course.load_courses(), Course.load_course())
    @test unmapped == String[]
    @test by["core"] == ["holes/symdiff/product_rule", "holes/symdiff/pvar_binding",
                         "items/L01-dispatch/specificity", "items/L02-concrete-types/abstract-field"]
    @test by["science"] == ["guided/epidemic:C:/Users/learner/work/epidemic", "guided/tidy:/home/learner/tidy"]
    @test isempty(by["scicomp"]) && isempty(by["sciml"])
    # an entry for something no course has is reported, never dropped silently
    _, um = Course.state_by_course(Dict("holes" => Dict("qsim/apply_gate" => Dict())), Dict(),
                                   Course.load_courses(), Course.load_course())
    @test um == ["holes/qsim/apply_gate"]
end

P_with(; compare = "isequal", checker = "", packages = String[]) =
    Course.Problem("p", "t", "core", String[], "", "f", "f(x) = x", "", ["1"], "", compare, checker, 1e-8, true,
                   false, String[], nothing, [Course.Variant("v", "", ["incorrect"])], 1, 1, packages)

@testset "concept questions: structure" begin
    Q(; kind = "choice", prompt = "Which?", code = "", choices = ["a", "b"], answer = 1, explain = "because",
      mis = ["", "thinks b"]) = Course.Question(kind, prompt, code, choices, answer, explain, mis)
    @test Course.question_problems(Q()) == String[]
    @test any(contains("misconception"), Course.question_problems(Q(; mis = ["", ""])))      # every wrong choice
    @test any(contains("right answer"), Course.question_problems(Q(; mis = ["oops", "thinks b"])))
    @test any(contains("index"), Course.question_problems(Q(; answer = 3)))
    @test any(contains("differ"), Course.question_problems(Q(; choices = ["a", "a "])))
    @test any(contains("needs code"), Course.question_problems(Q(; kind = "output")))
    @test any(contains("2 to 6"), Course.question_problems(Q(; choices = ["a"], mis = [""])))
    # an output question's key is measured: it must equal the recorded output, and only one choice may
    u = Course.Unit("99-x", "x", "core", "base", "ready", "s", String[], String[], String[], String[],
                    [Course.Section("s", "b", Course.Example[], [Q(; kind = "output", code = "1 + 1", choices = ["2", "3"])])],
                    Course.Problem[])
    k = Course.example_key("1 + 1", "repl")
    @test Course.recorded_code(u) == [("1 + 1", "repl")]
    @test Practice.question_key_problems(u, Dict("examples" => Dict(k => Dict("output" => "2\n")))) == String[]
    @test length(Practice.question_key_problems(u, Dict("examples" => Dict(k => Dict("output" => "3\n"))))) == 1
    # a custom compare needs a checker and only then
    bad(p) = Course.validate_course([Course.Unit(u.id, u.title, u.track, u.env, u.status, u.summary, u.kcs,
        String[], u.outline, u.lessons, u.sections, [p])]; strict = false)
    @test any(contains("checker"), bad(P_with(compare = "custom")))
    @test any(contains("not in course/envs"), bad(P_with(packages = ["Flux"])))
end

@testset "course prose: no filler phrases" begin
    u = Course.Unit("99-x", "x", "core", "base", "ready", "A seamless way to do it.", String[], String[], String[],
                    String[], [Course.Section("s", "Plain text, with `robust` in code and an em dash — here.", Course.Example[],
                                              Course.Question[])], Course.Problem[])
    probs = Course.prose_problems(u)
    @test any(contains("\"seamless\""), probs)
    @test !any(contains("\"robust\""), probs)          # inside inline code: not prose
    @test any(contains("em dash"), probs)
    @test all(isempty, Course.prose_problems.(Course.load_course()))
end

@testset "example notices: shown under the output, exported to the site" begin
    @test Course.Example("1", true, "c", "repl").notice == ""                  # optional
    exs = [e for s in SiteData.course_data()["units"] for sec in s["sections"] for e in sec["examples"]]
    @test all(e -> haskey(e, "notice"), exs) && any(e -> startswith(e["notice"], "Notice"), exs)
    # a caption is read before the example runs: it must not comment on the result
    @test !any(e -> occursin(r"\bNotice\b", e.caption), [e for u in Course.load_course() for s in u.sections for e in s.examples])
end

@testset "concept questions: the answer is not given away by its length" begin
    q(choices, answer) = Course.Question("choice", "p", "", choices, answer, "e", [i == answer ? "" : "m" for i in eachindex(choices)])
    unit(qs) = Course.Unit("99-x", "x", "core", "base", "ready", "s", String[], String[], String[], String[],
                           [Course.Section("s", "b", Course.Example[], qs)], Course.Problem[])
    long_key = q(["a much longer, careful and qualified answer", "short", "brief"], 1)
    fair = q(["short", "a much longer distractor than the key", "brief key"], 3)
    @test isempty(Course.question_balance_problems(unit([long_key, long_key, fair, fair, fair])))     # 2 of 5 <= 40%
    @test !isempty(Course.question_balance_problems(unit([long_key, long_key, long_key, fair, fair])))
    @test isempty(Course.question_balance_problems(unit([long_key, long_key, long_key])))           # too few to judge
    terse_key = q(["a much longer, careful distractor", "another long and detailed distractor", "key"], 3)
    @test any(contains("shortest"), Course.question_balance_problems(unit([terse_key, terse_key, terse_key, fair, fair])))
    @test all(isempty, Course.question_balance_problems.(Course.load_course()))
end

# A problem shell for assess(): only the fields assess reads matter.
const P = Course.Problem("p", "t", "core", String[], "", "f", "", "", ["1"], "", "isequal", "", 1e-8, true,
                         false, String[], Course.Perf("n", [1000, 16000], false), Course.Variant[], 1, 1, String[])

raw_perf(; sub = (1e3, 16e3), ref = (1e3, 16e3), bytes = (0, 0), locals = Any[], rk = "concrete") =
    Dict("status" => "ok", "phase" => "done",
         "correctness" => Dict("passed" => 5, "total" => 5, "explicit" => 1, "failures" => Any[]),
         "perf" => Dict("sizes" => Any[Dict("n" => 1000, "sub_ns" => sub[1], "ref_ns" => ref[1], "sub_bytes" => bytes[1], "ref_bytes" => 0),
                                       Dict("n" => 16000, "sub_ns" => sub[2], "ref_ns" => ref[2], "sub_bytes" => bytes[2], "ref_bytes" => 0)],
                        "return_sub" => "Int64", "return_sub_kind" => rk, "return_ref" => "Int64",
                        "return_ref_kind" => "concrete", "locals" => locals))

@testset "grader verdicts (assess on synthetic measurements)" begin
    r = Practice.assess(P, raw_perf())
    @test r["status"] == "passed" && r["verdicts"] == ["correct", "fast"]
    @test r["performance"]["overall"] == "excellent"

    r = Practice.assess(P, raw_perf(sub = (1e4, 2.56e6)))            # 160x slower, n^2 growth
    @test issubset(["correct", "slow", "scaling"], r["verdicts"])
    @test r["performance"]["overall"] == "needs-work"
    @test any(f -> startswith(f["title"], "Growth: about n^2.0"), r["feedback"])

    r = Practice.assess(P, raw_perf(bytes = (8000, 128000)))
    @test "allocates" in r["verdicts"] && r["performance"]["overall"] == "good"
    @test "allocates" ∉ Practice.assess(P, raw_perf(bytes = (64, 64)))["verdicts"]   # within slack

    unions = Any[Dict("name" => "s", "type" => "Union{Float64, Int64}", "kind" => "abstract")]
    r = Practice.assess(P, raw_perf(locals = unions))
    @test "unstable" in r["verdicts"]
    @test any(f -> occursin("zero(eltype(v))", f["detail"]), r["feedback"])

    benign = Any[Dict("name" => "i", "type" => "Union{Nothing, Int64}", "kind" => "small-union")]
    @test "unstable" ∉ Practice.assess(P, raw_perf(locals = benign))["verdicts"]
    @test "unstable" in Practice.assess(P, raw_perf(rk = "abstract"))["verdicts"]

    fail = Dict("status" => "ok", "correctness" => Dict("passed" => 3, "total" => 5, "explicit" => 1,
        "failures" => Any[Dict("case" => 2, "input" => "f(2)", "reason" => "wrong type", "expected" => "4::Int64",
                               "got" => "4.0::Float64", "shown" => false)]))
    r = Practice.assess(P, fail)
    @test r["status"] == "failed" && r["verdicts"] == ["incorrect"] && r["performance"] === nothing
    @test occursin("2 of 5", r["feedback"][1]["title"])

    @test Practice.assess(P, Dict("status" => "load-error", "message" => "ERROR: x"))["status"] == "load-error"
    @test Practice.assess(P, nothing; timed_out = true)["status"] == "timeout"
    # correct, but the performance phase timed out: still correct, flagged slow
    r = Practice.assess(P, Dict("status" => "ok", "phase" => "performance",
                                "correctness" => Dict("passed" => 5, "total" => 5, "explicit" => 1, "failures" => Any[]));
                        timed_out = true)
    @test r["status"] == "passed" && "slow" in r["verdicts"]

    # an exception while measuring is reported as such, never as "slow"
    r = Practice.assess(P, Dict("status" => "ok", "phase" => "done", "perf_error" => "ERROR: MethodError: boom",
                                "correctness" => Dict("passed" => 5, "total" => 5, "explicit" => 1, "failures" => Any[])))
    @test r["status"] == "passed" && r["verdicts"] == ["correct"]
    @test any(f -> f["title"] == "Performance could not be measured" && occursin("boom", f["detail"]), r["feedback"])

    # instability is relative: an abstract local the reference also has is not the learner's doing
    anyv = Any[Dict("name" => "args", "type" => "Vector{Any}", "kind" => "abstract-container")]
    shared = raw_perf(locals = anyv); shared["perf"]["ref_locals"] = anyv
    @test "unstable" ∉ Practice.assess(P, shared)["verdicts"]
    @test "unstable" in Practice.assess(P, raw_perf(locals = anyv))["verdicts"]

    # a local in a helper the learner defined counts, and the feedback names the helper
    helper = Any[Dict("name" => "acc", "type" => "Union{Float64, Int64}", "kind" => "abstract", "function" => "total")]
    r = Practice.assess(P, raw_perf(locals = helper))
    @test "unstable" in r["verdicts"]
    @test any(f -> occursin("`acc::Union{Float64, Int64}` in `total`", f["title"]) &&
                   occursin("`acc` in `total` starts as one number type", f["detail"]), r["feedback"])
end

@testset "starter must mention the entry (bang names too)" begin
    units = Course.load_course()
    _, p = Course.find_problem(units, "sum-of-squares")
    bang(entry, starter) = Course.Problem(p.id, p.title, p.difficulty, p.kcs, p.prompt, entry, starter, p.reference,
        p.cases, p.gen, p.compare, p.checker, p.rtol, p.check_type, p.compare_args, p.hints, p.perf, p.variants, p.threads, p.repeats, p.packages)
    u = units[1]
    probs(q) = Course.validate_course([Course.Unit(u.id, u.title, u.track, u.env, u.status, u.summary, u.kcs,
        String[], u.outline, u.lessons, u.sections, [q])]; strict = false)
    mentions(e, s) = !any(m -> occursin("starter does not mention", m), probs(bang(e, s)))
    @test mentions("scale!", "function scale!(v)\nend")
    @test !mentions("scale!", "function scale!!(v)\nend")
    @test !mentions("scale!", "function rescale!(v)\nend")
    @test !mentions("scale", "function scale_all(v)\nend")
end

@testset "output scrubbing" begin
    s = "  @ LinearAlgebra " * joinpath(Sys.STDLIB, "LinearAlgebra", "src", "uniformscaling.jl") * ":145"
    @test Practice.scrub(s) == "  @ LinearAlgebra <stdlib>/LinearAlgebra/src/uniformscaling.jl:145"
    # counters that move whenever the child script changes
    @test Practice.scrub("  @ #28 at line 15") == "  @ anonymous function at line 15"
    @test Practice.scrub("running in world age 31617, while current world is 31618.") ==
          "running in world age W, while current world is W+1."
    @test Practice.scrub("world age 5, while current world is 9") == "world age 5, while current world is 9"
end

@testset "verify compares what the course teaches" begin
    # the two lists CI and the local image printed for the same MethodError
    err(c) = "[1, 2]\nERROR: MethodError: no method matching +(::Vector{Int64}, ::Int64)\n\nClosest candidates are:\n$c  ...\n\n  @ top-level scope at line 5\n"
    a = err("  +(!Matched::Missing, ::Number)\n   @ Base missing.jl:123\n")
    b = err("  +(!Matched::BigInt, ::Union{Int16, Int32, Int64, Int8})\n   @ Base gmp.jl:555\n")
    @test a != b && Practice.comparable(a) == Practice.comparable(b)
    @test Practice.same_example(Dict("output" => a, "ok" => false), Dict("output" => b, "ok" => false))
    @test !Practice.same_example(Dict("output" => a, "ok" => false), Dict("output" => a, "ok" => true))
    # the error, the lines around it and the line number still count
    @test Practice.comparable(a) != Practice.comparable(replace(b, "line 5" => "line 6"))
    @test Practice.comparable(a) != Practice.comparable(replace(b, "[1, 2]" => "[1, 3]"))
    @test Practice.comparable("x\nClosest candidates are:\n  f(::Int)\n") == Practice.comparable("x\nClosest candidates are:\n  f(::Float64)")

    @test Practice.same_sample("0.4246224f0", "0.42462245f0")
    @test Practice.same_sample("(3, 0.9166666666666666)", "(3, 0.9166666666666667)")
    @test !Practice.same_sample("(3, 0.91)", "(2, 0.91)")
    @test !Practice.same_sample("0.4246f0", "0.4247f0")
    @test !Practice.same_sample("2//3", "2//5")
    @test !Practice.same_sample("Float32[1.0]", "Float64[1.0]")
    @test !Practice.same_sample("2-element Vector{Float32}:\n 1.0\n 2.0", "1-element Vector{Float32}:\n 1.0")
    st = Dict("p" => Any[Dict("call" => "f(1)", "result" => "1.00000001")])
    @test Practice.sample_problems("u", st, Dict("p" => Any[Dict("call" => "f(1)", "result" => "1.0")])) == String[]
    pr = Practice.sample_problems("u", st, Dict("p" => Any[Dict("call" => "f(1)", "result" => "1.1")]))
    @test length(pr) == 1 && occursin("--- recorded\n1.00000001\n--- now\n1.1", pr[1])
    @test length(Practice.sample_problems("u", nothing, Dict())) == 1
end

@testset "a command that never answers does not block the sandbox check" begin
    jl = Base.julia_cmd()
    t = @elapsed r = Runner.ok_cmd(`$jl --startup-file=no -e "sleep(600)"`; timeout = 3)
    @test !r && t < 60
    @test Runner.ok_cmd(`$jl --startup-file=no -e "exit(0)"`)
    @test !Runner.ok_cmd(`$jl --startup-file=no -e "exit(1)"`)
end

@testset "sandbox container: flags, protocol, staleness" begin
    a = Runner.docker_args(; project_env = "data", threads = 4, name = "julia-tutor-x")
    for f in ("--network=none", "--read-only", "--cap-drop=ALL", "--security-opt=no-new-privileges", "-i", "--rm")
        @test f in a
    end
    @test "--pids-limit=$(Runner.CONTAINER_PIDS)" in a && "--memory=$(Runner.CONTAINER_MEMORY)" in a
    @test "--memory-swap=$(Runner.CONTAINER_MEMORY)" in a          # no swap beyond the memory limit
    @test "--heap-size-hint=$(Runner.CONTAINER_HEAP_HINT)" in a       # GC collects before the kernel kills
    # a container killed for memory says so instead of "crashed" (docker only:
    # a plain process's 137 is any SIGKILL; a timeout's kill is reported as one)
    let old = Runner.SANDBOX[]
        try
            Runner.SANDBOX[] = :docker
            @test Practice.out_of_memory(Runner.OOM_EXIT, false)
            @test !Practice.out_of_memory(Runner.OOM_EXIT, true) && !Practice.out_of_memory(1, false)
            Runner.SANDBOX[] = :none
            @test !Practice.out_of_memory(Runner.OOM_EXIT, false)
        finally
            Runner.SANDBOX[] = old
        end
    end
    @test !any(x -> startswith(x, "--mount") || x in ("-v", "--volume", "--privileged") || startswith(x, "--network=h"), a)
    @test "--threads=4" in a && "--project=/tutor/envs/data" in a && last(a) == "/tutor/child/contained.jl"
    @test a[findfirst(==("--user"), a) + 1] != "0:0"
    @test "--cpus=5" in a                                                         # threads + 1
    @test "--cpus=2" in Runner.docker_args(; project_env = "base", threads = 4, name = "x", maxcpus = 2)  # Docker's VM has 2

    # the files come back between the markers, after what the code printed
    # (base64: a figure is binary, TOML strings must be UTF-8)
    files_block(name, bytes) = Runner.FILES_BEGIN * "\n\"$name\" = \"$(base64encode(bytes))\"\n" * Runner.FILES_END * "\n"
    png = UInt8[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0xff, 0x00]   # not valid UTF-8
    out = "hello\n\n" * files_block("result.toml", codeunits("x = 1\n"))
    log, files = Runner.split_files(out)
    @test log == "hello\n" && String(copy(files["result.toml"])) == "x = 1\n"
    @test Runner.split_files("\n" * files_block("figure.png", png))[2]["figure.png"] == png
    # code that prints a fake marker early cannot replace the real files
    log, files = Runner.split_files("x" * files_block("r", codeunits("fake")) * out)
    @test collect(keys(files)) == ["result.toml"]
    @test Runner.split_files("crashed\n") == ("crashed\n", Dict{String,Vector{UInt8}}())

    # the image label covers the child scripts and the environments
    names = first.(Runner.sandbox_inputs())
    @test "child/sandbox.jl" in names && "child/contained.jl" in names && "envs/data/Manifest.toml" in names
    @test length(Runner.sandbox_hash()) == 64
    # every course environment gets its own COPY in the Dockerfile (one layer each)
    df = replace(read(joinpath(Runner.SANDBOX_DIR, "Dockerfile"), String), "\r\n" => "\n")
    for e in readdir(joinpath(Course.COURSE_DIR, "envs"))
        @test occursin("COPY envs/$e /tutor/envs/$e\n", df)
        isfile(joinpath(Course.COURSE_DIR, "envs", e, "Manifest.toml")) && @test occursin("/tutor/envs/$e && rm", df)
    end
end

@testset "sandbox server request policy" begin
    tok = "ab"^24
    cfg = Server.ServerConfig(; port = 8765, token = tok, units = Course.load_course())
    ran = String[]
    fake_run(code; env, mode, timeout) = (push!(ran, code); Practice.RunResult("3\n", true, false, 0.1,
        [Practice.Image("figure.png", "image/png", UInt8[0x89, 0x50, 0x4e, 0x47])]))
    fake_grade(p, code; env) = Dict("problem" => p.id, "status" => "passed")
    req(m, path; h = Dict{String,String}(), body = "") = Server.handle(cfg,
        Server.Request(m, path, merge(Dict("host" => "127.0.0.1:8765"), h), body); run = fake_run, gradefn = fake_grade)
    auth = Dict("authorization" => "Bearer $tok")
    site = Dict("origin" => "https://adamezzat1.github.io")
    hdr(r, k) = (i = findfirst(p -> p.first == k, r.headers); i === nothing ? "" : r.headers[i].second)

    @test req("GET", "/api/health"; h = auth).status == 200
    @test JSON.parse_json(req("GET", "/api/health"; h = auth).body)["sandbox"] == string(Runner.SANDBOX[])
    @test req("GET", "/api/health").status == 401                                          # no token
    @test req("GET", "/api/health"; h = Dict("authorization" => "Bearer " * "cd"^24)).status == 401
    @test req("GET", "/api/health"; h = Dict("authorization" => "Bearer é" * tok)).status == 401  # no index error
    @test req("GET", "/api/health"; h = merge(auth, Dict("host" => "evil.example:8765"))).status == 421  # DNS rebinding
    @test req("GET", "/api/health"; h = merge(auth, Dict("origin" => "https://evil.example"))).status == 403
    r = req("GET", "/api/health"; h = merge(auth, site))
    @test r.status == 200 && hdr(r, "Access-Control-Allow-Origin") == site["origin"]

    pre = req("OPTIONS", "/api/run"; h = merge(site, Dict("access-control-request-private-network" => "true")))
    @test pre.status == 204 && hdr(pre, "Access-Control-Allow-Private-Network") == "true"
    @test occursin("Authorization", hdr(pre, "Access-Control-Allow-Headers"))
    @test req("OPTIONS", "/api/run"; h = Dict("origin" => "https://evil.example")).status == 403

    r = req("POST", "/api/run"; h = auth, body = "{\"code\": \"1+2\"}")
    @test r.status == 200 && ran == ["1+2"]
    img = only(JSON.parse_json(r.body)["images"])                       # figures travel as base64
    @test img["mime"] == "image/png" && base64decode(img["data"]) == UInt8[0x89, 0x50, 0x4e, 0x47]
    @test req("POST", "/api/run"; h = auth, body = "{bad").status == 400
    @test req("POST", "/api/run"; h = auth, body = "{\"code\": 1}").status == 400
    @test req("POST", "/api/run"; h = auth, body = "{\"code\": \"x\", \"env\": \"../../etc\"}").status == 400
    @test req("POST", "/api/run"; h = Dict{String,String}(), body = "{\"code\": \"x\"}").status == 401
    @test length(ran) == 1                                                                  # nothing else ran
    @test req("POST", "/api/grade"; h = auth, body = "{\"code\": \"x\", \"problem\": \"nope\"}").status == 404
    r = req("POST", "/api/grade"; h = auth, body = "{\"code\": \"x\", \"problem\": \"fahrenheit\"}")
    @test r.status == 200 && JSON.parse_json(r.body)["problem"] == "fahrenheit"
    @test req("GET", "/api/run"; h = auth).status == 405
    @test req("GET", "/etc/passwd"; h = auth).status == 404

    # HTTP parsing limits
    io = IOBuffer("POST /api/run HTTP/1.1\r\nHost: 127.0.0.1:8765\r\nContent-Length: 999999999\r\n\r\n")
    @test_throws Server.BadRequest Server.read_request(io)
    io = IOBuffer("POST /api/run?x=1 HTTP/1.1\r\nHost: 127.0.0.1:8765\r\nContent-Length: 2\r\n\r\n{}")
    rq = Server.read_request(io)
    @test rq.path == "/api/run" && rq.body == "{}" && rq.headers["host"] == "127.0.0.1:8765"
end

if !FAST
    @testset "sandbox child: run and grade for real" begin
        r = Practice.run_code("x = 1\nfor i in 1:3\n    x += i\nend\nx")      # REPL soft scope
        @test r.ok && r.output == "7\n"
        r = Practice.run_code("x = 1\nfor i in 1:3\n    x += i\nend\nx"; mode = "file")
        @test !r.ok && occursin("ERROR: UndefVarError", r.output)
        r = Practice.run_code("rand(1:100);\nprintln(rand(1:100))")             # seeded
        @test r.output == Practice.run_code("rand(1:100);\nprintln(rand(1:100))").output
        @test Practice.run_code("while true end"; timeout = 3).timed_out
        # figures: a returned value that renders as an image, and files the code saves
        fig = "struct Fig end\nBase.show(io::IO, ::MIME\"image/svg+xml\", ::Fig) = print(io, \"<svg xmlns='http://www.w3.org/2000/svg'/>\")\nFig()"
        r = Practice.run_code(fig)
        @test r.ok && r.output == "[figure: figure.svg]\n" && only(r.images).mime == "image/svg+xml"
        r = Practice.run_code("write(\"a.png\", UInt8[0x89, 0x50]); write(\"notes.txt\", \"x\"); 1")
        @test r.output == "1\n" && [i.name for i in r.images] == ["a.png"] && r.images[1].data == UInt8[0x89, 0x50]
        @test isempty(Practice.run_code("[1 2; 3 4]").images)                           # plain data is printed, not drawn
        # The learner's Main is empty, as in a fresh REPL: the child's helpers
        # (`sample`, `call`, `approx`, ...) would shadow package exports.
        @test Practice.run_code("filter(n -> !startswith(string(n), '#'), names(Main; all = true))").output ==
              Practice.run_code("[:Base, :Core, :Main, :TutorChild]").output
        @test Practice.run_code("sample(x) = 2x; call = 1; sample(3) + call").output == "7\n"
        @test Practice.run_code("Xoshiro(1)").output |> contains("UndefVarError")       # Random is not preloaded
        # a custom checker decides correctness
        cp = P_with(compare = "custom", checker = "(got, want) -> abs(got - want) < 0.5")
        cp = Course.Problem(cp.id, cp.title, cp.difficulty, cp.kcs, cp.prompt, cp.entry, cp.starter, "f(x) = x + 0.1",
            ["1.0"], cp.gen, cp.compare, cp.checker, cp.rtol, false, false, cp.hints, nothing, cp.variants, 1, 1, String[])
        @test Practice.grade(cp, "f(x) = x")["status"] == "passed"
        @test Practice.grade(cp, "f(x) = x + 1")["status"] == "failed"
        _, p = Course.find_problem(Course.load_course(), "sum-of-squares")
        g = Practice.grade(p, "sum_of_squares(n) = sum([i^2 for i in 1:n])")
        @test g["status"] == "passed" && "allocates" in g["verdicts"]
        g = Practice.grade(p, "sum_of_squares(n) = n")
        @test g["status"] == "failed"
        g = Practice.grade(p, "sum_of_squares(n) = (")
        @test g["status"] == "load-error"
        # a result whose `isequal` and `show` throw is a wrong answer, not a crash
        g = Practice.grade(p, """
            struct Boom end
            Base.isequal(::Boom, ::Any) = error("no compare")
            Base.show(::IO, ::Boom) = error("no show")
            sum_of_squares(n) = Boom()""")
        @test g["status"] == "failed"
        @test contains(repr(g), "could not compare") && contains(repr(g), "cannot be shown")
        # the type check reaches helpers, inlined or not
        g = Practice.grade(p, "function total(n)\n    s = 0\n    for i in 1:n\n        s += i^2 * 1.0\n    end\n    s\nend\n" *
                              "sum_of_squares(n) = round(Int, total(n))")
        @test g["status"] == "passed" && "unstable" in g["verdicts"]
        @test any(f -> occursin("in `total`", f["title"]), g["feedback"])
        g = Practice.grade(p, "sq(i) = i^2\nfunction sum_of_squares(n)\n    s = 0\n    for i in 1:n\n        s += sq(i)\n    end\n    s\nend")
        @test g["status"] == "passed" && "unstable" ∉ g["verdicts"]
        # threads: a racy sum passes on one thread and must fail when graded on several
        _, q = Course.find_problem(Course.load_course(), "parallel-chunk-sum")
        @test q.threads > 1 && q.repeats > 1
        racy = only(v for v in q.variants if startswith(v.label, "racy"))
        g = Practice.grade(q, racy.code)
        @test g["status"] == "failed" && occursin("data race", g["feedback"][1]["detail"])
    end

    # The same child in the container, when Docker and an up-to-date image are here.
    why = Runner.sandbox_problem()
    if why === nothing
        @testset "sandbox container: run and grade for real" begin
            Runner.SANDBOX[] = :docker
            try
                r = Practice.run_code("x = 1\nfor i in 1:3\n    x += i\nend\nx")
                @test r.ok && r.output == "7\n"
                r = Practice.run_code("println(\"out\"); error(\"boom\")")
                @test !r.ok && startswith(r.output, "out\nERROR: boom")
                @test Practice.run_code("using Sockets; connect(\"1.1.1.1\", 53)").ok == false     # no network
                r = Practice.run_code("touch(\"/tutor/child/x\")")                                  # read-only
                @test !r.ok && occursin("ERROR", r.output)
                r = Practice.run_code("isdir(\"/c\") || isdir(\"/Users\") || isdir(\"/home/\" * get(ENV, \"USER\", \"x\"))")
                @test r.output == "false\n"                                                         # no host files
                @test Practice.run_code("while true end"; timeout = 15).timed_out
                r = Practice.run_code("write(\"a.png\", UInt8[0x89, 0x50, 0xff]); 1")          # binary survives
                @test r.output == "1\n" && only(r.images).data == UInt8[0x89, 0x50, 0xff]
                _, p = Course.find_problem(Course.load_course(), "sum-of-squares")
                g = Practice.grade(p, "sum_of_squares(n) = sum([i^2 for i in 1:n])")
                @test g["status"] == "passed" && "allocates" in g["verdicts"]
                _, q = Course.find_problem(Course.load_course(), "parallel-chunk-sum")
                g = Practice.grade(q, only(v for v in q.variants if startswith(v.label, "racy")).code)
                @test g["status"] == "failed"
            finally
                Runner.SANDBOX[] = :none
            end
        end
    else
        @info "skipping the container tests: $why"
    end
end
