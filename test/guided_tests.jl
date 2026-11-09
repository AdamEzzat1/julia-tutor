# Tests for guided build projects (src/guided.jl, src/guided_driver.jl).
# Included from runtests.jl; FAST skips the subprocess run of the driver.

using JuliaTutor: Guided, Checker, Runner
using TOML, Base64

# The driver's module without its last two lines (which run a job), so its
# pieces can be tested in this process. It runs only our own test code here.
function load_driver_module()
    src = read(Guided.DRIVER, String)
    i = findlast("end # module GuidedDriver", src)
    m = Module(:DriverUnderTest)
    Base.include_string(m, src[1:last(i)], "guided_driver.jl")
    return m.GuidedDriver
end

# A tiny project in a temporary root, on the `base` env (stdlib only).
function mini_project(root)
    d = joinpath(root, "mini")
    mkpath(joinpath(d, "reference", "src")); mkpath(joinpath(d, "reference", "test")); mkpath(joinpath(d, "acceptance"))
    write(joinpath(d, "project.toml"), """
    name = "mini"
    package = "Mini"
    env = "base"
    status = "ready"
    title = "Mini"
    summary = "A test project."
    [[milestone]]
    id = 0
    title = "Layout"
    goal = "Make the package."
      [[milestone.behaviour]]
      id = "layout"
      kc = "packages"
      spec = "The module loads."
      hints = ["One.", "Two.", "Three."]
      test_hints = ["One.", "Two.", "Three."]
    [[milestone]]
    id = 1
    title = "Double"
    goal = "Write double."
    min_score = 1.0
    must_cover = ["doubles", "quiet"]
      [[milestone.api]]
      signature = "double(x) -> number"
      doc = "Twice x."
      [[milestone.behaviour]]
      id = "doubles"
      kc = "functions"
      spec = "double(x) is 2x."
      hints = ["Think about multiplication.", "Two times the input.", "Return 2 times x."]
      answer_tokens = ["2x", "2 * x"]
      test_hints = ["Test a value.", "Test 3.", "Test 3 and 0."]
      [[milestone.behaviour]]
      id = "quiet"
      kc = "functions"
      spec = "double logs nothing."
      hints = ["No logging.", "Remove the log line.", "No @info."]
      test_hints = ["Use @test_logs.", "With no patterns.", "@test_logs double(1)."]
    """)
    write(joinpath(d, "reference", "src", "Mini.jl"), "module Mini\nexport double\ndouble(x) = 2x\nend\n")
    write(joinpath(d, "reference", "test", "m0.jl"), "@testset \"loads\" begin\n    @test Mini isa Module\nend\n")
    write(joinpath(d, "reference", "test", "m1.jl"),
          "@testset \"double\" begin\n    @test double(3) == 6\n    @test_logs double(1)\nend\n")
    write(joinpath(d, "acceptance", "m0.jl"), "using Mini, Test\n@testset \"layout\" begin\n    @test Mini isa Module\nend\n")
    write(joinpath(d, "acceptance", "m1.jl"),
          "using Mini, Test\n@testset \"doubles\" begin\n    @test double(3) == 6\n    @test double(0) == 0\nend\n" *
          "@testset \"quiet\" begin\n    @test_logs double(2)\nend\n")
    write(joinpath(d, "mutants.toml"), """
    [[mutant]]
    id = "triple"
    milestone = 1
    behaviour = "doubles"
    file = "Mini.jl"
    find = "double(x) = 2x"
    replace = "double(x) = 3x"
    [[mutant]]
    id = "noisy"
    milestone = 1
    behaviour = "quiet"
    file = "Mini.jl"
    find = "double(x) = 2x"
    replace = "double(x) = (@info \\"doubling\\"; 2x)"
    """)
    return Guided.load_guided("mini"; root)
end

function student(root, name; src, test)
    d = joinpath(root, name)
    mkpath(joinpath(d, "src")); mkpath(joinpath(d, "test"))
    write(joinpath(d, "src", "Mini.jl"), src)
    write(joinpath(d, "test", "runtests.jl"), test)
    return d
end

run_rec(label; sets = Any[], total = nothing, extra...) =
    Dict{String,Any}("label" => label, "testsets" => sets, "toplevel_error" => "",
                     "total" => something(total, sum(s -> s["passed"] + s["failed"] + s["errored"], sets; init = 0)),
                     (String(k) => v for (k, v) in extra)...)
tset(name; passed = 1, failed = 0, errored = 0, errors = String[], messages = String[]) =
    Dict{String,Any}("name" => name, "passed" => passed, "failed" => failed, "errored" => errored,
                     "errors" => errors, "messages" => messages)

@testset "guided projects" begin
    @testset "every project validates (structure, hints, prose)" begin
        ps = Guided.load_all()
        @test length(ps) >= 8
        @test count(p -> p.status == "ready", ps) >= 2
        for p in ps
            @test Guided.validate(p) == String[]
        end
        @test Set(p.env for p in ps) ⊆ Set(readdir(joinpath(JuliaTutor.ROOT, "course", "envs")))
    end

    @testset "validate catches authoring mistakes" begin
        root = mktempdir()
        p = mini_project(root)
        @test Guided.validate(p) == String[]
        # A level-1 hint that gives the answer away.
        txt = read(joinpath(p.dir, "project.toml"), String)
        write(joinpath(p.dir, "project.toml"), replace(txt, "\"Think about multiplication.\"" => "\"Return 2x.\""))
        # (`has(s)` checks that s occurs in a message; curried `occursin(s)` is the reverse.)
        has(s) = msg -> occursin(s, msg)
        @test any(has("level-1 hint contains the answer token `2x`"), Guided.validate(Guided.load_guided("mini"; root)))
        # Level 3 may point at the line, never contain the fix.
        write(joinpath(p.dir, "project.toml"), replace(txt, "\"Return 2 times x.\"" => "\"Write 2 * x.\""))
        @test any(has("level-3 hint contains the answer token `2 * x`"), Guided.validate(Guided.load_guided("mini"; root)))
        # A project name from a student's .guided file is a plain name only.
        @test_throws ErrorException Guided.load_guided("../mini"; root)
        @test_throws ErrorException Guided.load_guided("nosuch"; root)
        # Filler and em dashes in prose.
        write(joinpath(p.dir, "project.toml"), replace(txt, "A test project." => "A robust test project — with a dash."))
        pr = Guided.validate(Guided.load_guided("mini"; root))
        @test any(has("filler phrase \"robust\""), pr) && any(has("em dash"), pr)
        # A must_cover behaviour without a mutant.
        write(joinpath(p.dir, "project.toml"), txt)
        write(joinpath(p.dir, "mutants.toml"), "")
        @test any(has("must_cover quiet has no mutant"), Guided.validate(Guided.load_guided("mini"; root)))
    end

    @testset "mutants apply exactly once" begin
        p = mini_project(mktempdir())
        ref = Guided.reference_files(p)
        mf = Guided.mutant_files(p, p.mutants[1], ref)
        @test occursin("3x", mf["src/Mini.jl"]) && !occursin("2x", mf["src/Mini.jl"])
        @test ref["src/Mini.jl"] == "module Mini\nexport double\ndouble(x) = 2x\nend\n"   # the reference is untouched
        bad = Guided.Mutant("m", 1, "doubles", "Mini.jl", "not in the file", "")
        @test_throws ErrorException Guided.mutant_files(p, bad, ref)
        twice = Dict("src/Mini.jl" => "a\na\n")
        @test_throws ErrorException Guided.mutant_files(p, Guided.Mutant("m", 1, "doubles", "Mini.jl", "a", "b"), twice)
    end

    @testset "the job: runs, order, and what is sent" begin
        p = mini_project(mktempdir())
        st = Dict("src/Mini.jl" => "module Mini end", "test/runtests.jl" => "using Mini, Test", "test/m1.jl" => "# mine")
        job = Guided.check_job(p, st, 1)
        labels = [r["label"] for r in job["runs"]]
        @test labels[1:3] == ["acceptance m0", "acceptance m1", "own tests on own code"]
        @test Set(labels[4:end]) == Set(["own tests on reference", "own tests on mutant triple", "own tests on mutant noisy"])
        @test Guided.check_job(p, st, 0)["runs"][end]["label"] == "own tests on reference"   # no milestone-1 mutants at 0
        @test Guided.check_job(p, st, 1)["runs"] == job["runs"]                             # the shuffle is seeded
        # Neutral names: no directory says which implementation it holds.
        byl = Dict(r["label"] => r["impl"] for r in job["runs"])
        tops = Set(first(split(k, '/')) for k in keys(job["files"]))
        @test tops == Set(["student", "acceptance", byl["own tests on reference"], byl["own tests on mutant triple"],
                           byl["own tests on mutant noisy"]])
        @test all(d -> occursin(r"^impl_\d+$", d), setdiff(tops, ["student", "acceptance"]))
        @test issorted([Base.parse(Int, r["impl"][6:end]) for r in job["runs"][4:end]])          # run in name order
        # The reference's exemplary tests are not sent; the student's test files are, under each implementation.
        rd, td = byl["own tests on reference"], byl["own tests on mutant triple"]
        @test !any(k -> endswith(k, "test/m0.jl"), keys(job["files"]))
        @test job["files"]["$rd/test/m1.jl"] == "# mine"
        @test job["files"]["$td/test/runtests.jl"] == "using Mini, Test"
        @test occursin("3x", job["files"]["$td/src/Mini.jl"]) && occursin("2x", job["files"]["$rd/src/Mini.jl"])
        # The driver program embeds the job as base64 TOML.
        s = Guided.driver_source(job)
        m = match(r"^GUIDED_JOB = \"([A-Za-z0-9+/=]*)\"\n", s)
        @test m !== nothing
        @test TOML.parse(String(base64decode(m.captures[1])))["package"] == "Mini"
        # start creates data and a guide, no code.
        sf = Guided.start_files(Guided.load_guided("tidy"))
        @test haskey(sf, "GUIDE.md") && haskey(sf, "data/readings.csv")
        @test !any(k -> startswith(k, "src/") || startswith(k, "test/") || endswith(k, ".jl"), keys(sf))
    end

    @testset "driver: using rewrite and the recording test set" begin
        D = load_driver_module()
        rw(s) = D.rewrite(Meta.parse(s), :Mini)
        @test rw("using Mini") == Meta.parse("using .Mini")
        @test rw("using Mini, Test") == Meta.parse("using .Mini, Test")
        @test rw("import Mini: double") == Meta.parse("import .Mini: double")
        @test rw("using Mini.Sub") == Meta.parse("using .Mini.Sub")
        @test rw("begin\n using Mini\nend") == Meta.parse("begin\n using .Mini\nend")
        @test rw("using MiniOther") == Meta.parse("using MiniOther")
        @test rw("quote using Mini end") == Meta.parse("quote using Mini end")     # quoted code is data
        @test rw("import Mini as M") == Meta.parse("import .Mini as M")
        @test rw("using Mini: double as d") == Meta.parse("using .Mini: double as d")
        # Every non-passing result counts: Fail, Error, and @test_logs' LogTestFailure.
        ts = D.RecordingTestSet("root")
        Test.push_testset(ts)
        try
            @testset "inner" begin
                @test 1 == 1
                @test 1 == 2
                @test_logs (@info "x")
                @test error("boom")
                @test_broken false
            end
        finally
            Test.pop_testset()
        end
        flat = D.flatten!(Any[], ts, "", "/nowhere")
        inner = only(filter(s -> s["name"] == "root/inner", flat))
        @test (inner["passed"], inner["failed"], inner["errored"]) == (1, 2, 1)
        @test occursin("boom", only(inner["errors"]))
    end

    @testset "assess (pure): verdicts and one-thing-at-a-time feedback" begin
        p = mini_project(mktempdir())
        ok_runs() = Any[run_rec("acceptance m0"; sets = [tset("layout")]),
                        run_rec("acceptance m1"; sets = [tset("doubles"), tset("quiet")]),
                        run_rec("own tests on own code"; sets = [tset("t")]),
                        run_rec("own tests on reference"; sets = [tset("t")]),
                        run_rec("own tests on mutant triple"; sets = [tset("t"; passed = 0, failed = 1)]),
                        run_rec("own tests on mutant noisy"; sets = [tset("t"; passed = 0, failed = 1)])]
        raw = Dict{String,Any}("complete" => true, "runs" => ok_runs())
        r = Guided.assess(p, 1, raw)
        @test r["status"] == "passed" && r["verdicts"] == ["passed"] && r["score"] == 1.0
        # ADVICE never blocks (invariant 2); WARN does.
        adv = Checker.Finding("JT004", Checker.ADVICE, "src/Mini.jl", 1, 1, "advice")
        @test Guided.assess(p, 1, raw; findings = [adv])["status"] == "passed"
        warn = Checker.Finding("JT006", Checker.WARN, "test/runtests.jl", 1, 1, "float ==")
        @test "checker-warn" in Guided.assess(p, 1, raw; findings = [warn])["verdicts"]
        # Two failing behaviours: only the first gets its spec and hint; levels pick the hint.
        bad = ok_runs()
        bad[2] = run_rec("acceptance m1"; sets = [tset("doubles"; passed = 0, failed = 1), tset("quiet"; passed = 0, errored = 1, errors = ["UndefVarError: double"])])
        r = Guided.assess(p, 1, Dict{String,Any}("complete" => true, "runs" => bad); levels = Dict("acc:doubles" => 2))
        @test r["failing"] == ["doubles", "quiet"] && r["shown"] == ["acc:doubles"]
        txt = join([f["title"] * "\n" * f["detail"] for f in r["feedback"]], "\n")
        @test occursin("Hint 2: Two times the input.", txt)
        @test !occursin("Think about multiplication", txt)            # one level, not all
        @test occursin("Also not right yet: `quiet`", txt)
        @test !occursin("No logging.", txt)                            # quiet's hint is not shown yet
        # Tests that disagree with the spec, an empty suite, weak tests.
        dis = ok_runs(); dis[4] = run_rec("own tests on reference"; sets = [tset("t"; failed = 1, messages = ["Test Failed: expects 7"])])
        r = Guided.assess(p, 1, Dict{String,Any}("complete" => true, "runs" => dis))
        @test "tests-fail-reference" in r["verdicts"] && r["score"] === nothing
        @test occursin("expects 7", join([f["detail"] for f in r["feedback"]]))
        none = ok_runs(); none[4] = run_rec("own tests on reference"; sets = [tset("t"; passed = 0)])
        @test "no-tests" in Guided.assess(p, 1, Dict{String,Any}("complete" => true, "runs" => none))["verdicts"]
        weak = ok_runs(); weak[6] = run_rec("own tests on mutant noisy"; sets = [tset("t")])
        r = Guided.assess(p, 1, Dict{String,Any}("complete" => true, "runs" => weak))
        @test "weak-tests" in r["verdicts"] && r["surviving"] == ["noisy"] && r["score"] == 0.5
        @test occursin("do not notice when `quiet` breaks", join([f["title"] for f in r["feedback"]]))
        @test !occursin("@info", join([f["detail"] for f in r["feedback"]]))   # the mutant's edit is never shown
        @test occursin("Not covered: `quiet`", join([f["title"] for f in r["feedback"]]))
        # An acceptance file that stops outside its test sets (a missing API name) is not a pass.
        top = ok_runs(); top[2] = run_rec("acceptance m1"; sets = Any[], toplevel_error = "UndefVarError: `double` not defined")
        r = Guided.assess(p, 1, Dict{String,Any}("complete" => true, "runs" => top))
        @test "acceptance-fail" in r["verdicts"] && r["status"] != "passed"
        @test !occursin("every acceptance check passes", join([f["title"] for f in r["feedback"]]))
        # A test that calls a helper the reference lacks gets the API message, not "disagrees with the spec".
        off = ok_runs()
        off[4] = run_rec("own tests on reference"; sets = [tset("t"; passed = 0, errored = 1, errors = ["UndefVarError(:helper)"])])
        txt = join([f["detail"] for f in Guided.assess(p, 1, Dict{String,Any}("complete" => true, "runs" => off))["feedback"]])
        @test occursin("does not define", txt) && !occursin("disagree with the milestone spec", txt)
        # Per-milestone score: old tests that kill every earlier fault do not carry a later milestone.
        tp = Guided.load_guided("tidy")
        m = 3
        own3 = [x for x in tp.mutants if x.milestone == m]
        # Each earlier milestone's faults all killed; of milestone 3's own, only the first.
        killed(x) = x.milestone < m || x.id == own3[1].id
        runs = Any[[run_rec("acceptance m$k"; sets = [tset("x")]) for k in 0:m]...,
                   run_rec("own tests on own code"; sets = [tset("t")]), run_rec("own tests on reference"; sets = [tset("t")]),
                   [run_rec("own tests on mutant $(x.id)"; sets = [tset("t"; passed = killed(x) ? 0 : 1, failed = killed(x) ? 1 : 0)])
                    for x in tp.mutants if 1 <= x.milestone <= m]...]
        r = Guided.assess(tp, m, Dict{String,Any}("complete" => true, "runs" => runs))
        @test r["score"] == 1 / length(own3) && "weak-tests" in r["verdicts"]
        # must_cover: a high score that leaves a required behaviour uncovered still fails.
        ms3 = Guided.milestone(tp, m)
        c = first(b for b in ms3.must_cover if count(x -> x.behaviour == b, own3) == 1)
        killed2(x) = x.milestone < m || x.behaviour != c
        runs2 = [startswith(q["label"], "own tests on mutant ") ?
                 (x = only(filter(y -> q["label"] == "own tests on mutant $(y.id)", tp.mutants));
                  run_rec(q["label"]; sets = [tset("t"; passed = killed2(x) ? 0 : 1, failed = killed2(x) ? 1 : 0)])) : q
                 for q in runs]
        r = Guided.assess(tp, m, Dict{String,Any}("complete" => true, "runs" => runs2))
        @test r["score"] >= ms3.min_score && "weak-tests" in r["verdicts"]
        @test occursin("Not covered: `$c`", join([f["title"] for f in r["feedback"]]))
        # Timeout: says where.
        r = Guided.assess(p, 1, nothing; timed_out = true, log = "<<<guided-stage>>> acceptance m0\n<<<guided-stage>>> own tests on reference\n")
        @test r["verdicts"] == ["timeout"] && occursin("own tests on reference", r["feedback"][1]["title"])
    end

    @testset "state: hint levels fade in, reset on success" begin
        p = mini_project(mktempdir())
        st = Dict{String,Any}()
        key = "mini:/x"
        fail = Dict{String,Any}("milestone" => 1, "status" => "not-yet", "verdicts" => ["acceptance-fail"],
                                "failing" => ["doubles", "quiet"], "surviving" => String[], "shown" => ["acc:doubles"])
        for _ in 1:4
            Guided.record!(st, key, fail, p)
        end
        lv = Guided.levels_from(st, key)
        @test Guided.hint_level(lv, "acc:doubles") == 3            # capped at 3
        @test Guided.hint_level(lv, "acc:quiet") == 1              # failing but never shown: still level 1
        Guided.record!(st, key, Dict{String,Any}("milestone" => 1, "status" => "not-yet", "verdicts" => ["timeout"],
                                                 "failing" => String[], "surviving" => String[], "shown" => String[]), p)
        @test Guided.hint_level(Guided.levels_from(st, key), "acc:doubles") == 3   # a timeout changes nothing
        pass = Dict{String,Any}("milestone" => 1, "status" => "passed", "verdicts" => ["passed"],
                                "failing" => String[], "surviving" => String[], "shown" => String[])
        # A check whose tests fail on the reference runs no mutants: test-hint streaks stay.
        st2 = Dict{String,Any}("projects" => Dict{String,Any}(key => Dict{String,Any}("passed" => Int[],
                                                              "streaks" => Dict{String,Any}("test:quiet" => 2))))
        Guided.record!(st2, key, Dict{String,Any}("milestone" => 1, "status" => "not-yet", "verdicts" => ["tests-fail-reference"],
                                                  "failing" => String[], "surviving" => String[], "shown" => String[]), p)
        @test Guided.hint_level(Guided.levels_from(st2, key), "test:quiet") == 3
        Guided.record!(st, key, pass, p)
        @test Guided.hint_level(Guided.levels_from(st, key), "acc:doubles") == 1
        @test Guided.next_milestone(p, st, key) == 0
        Guided.record!(st, key, merge(pass, Dict("milestone" => 0)), p)
        @test Guided.next_milestone(p, st, key) == 1
    end

    @testset "perf: format, validation, source and merge (pure)" begin
        root = mktempdir()
        p0 = mini_project(root)
        @test all(m -> m.perf === nothing, p0.milestones)
        open(joinpath(root, "mini", "project.toml"), "a") do io
            # Appended after milestone 1's last behaviour: a subtable of milestone 1.
            write(io, "  [milestone.perf]\n  entry = \"double\"\n  cases = [\"3\", \"0.5\"]\n  args = \"rand(rng, n)\"\n  sizes = [1000, 10000]\n")
        end
        p = Guided.load_guided("mini"; root)
        s = Guided.milestone(p, 1).perf
        @test s.entry == "double" && s.required && s.fail_on == Guided.PERF_FAIL_ON && s.compare == "isapprox"
        @test isempty(Guided.validate(p))
        @test occursin("Performance: `double`", Guided.show_milestone(p, 1))
        bad = Guided.PerfSpec("triple", String[], "", [1, 2, 3], false, "approx", 1e-8, true, ["fast"])
        m1 = Guided.milestone(p, 1)
        pb = Guided.GuidedProject(p.name, p.dir, p.package, p.env, p.status, p.title, p.summary, p.kcs, p.reading,
                                  [p.milestones[1], Guided.Milestone(m1.id, m1.title, m1.goal, m1.api, m1.behaviours,
                                                                      m1.must_cover, m1.min_score, m1.questions, bad)],
                                  p.mutants, p.fixtures)
        probs = join(Guided.validate(pb), "\n")
        for w in ("is not in the milestone's API", "no cases", "no args", "one or two sizes", "isequal or isapprox", "fail_on `fast`")
            @test occursin(w, probs)
        end
        # One source text: include lines inlined (relative to the including file), others kept.
        files = Dict("src/Mini.jl" => "module Mini\ninclude(\"part.jl\")\ninclude(\"gone.jl\")\nend\n",
                     "src/part.jl" => "double(x) = 2x\n")
        src = Guided.perf_source(files, "Mini", "double")
        @test occursin("double(x) = 2x", src) && !occursin("include(\"part.jl\")", src)
        @test occursin("include(\"gone.jl\")", src)                 # not in the folder: left for the grader to report
        @test endswith(src, "using .Mini: double\n")
        @test occursin("error(", Guided.perf_source(Dict{String,String}(), "Mini", "double"))
        pp = Guided.perf_problem(p, 1)
        @test pp.entry == "double" && pp.perf.sizes == [1000, 10000] && occursin("module Mini", pp.reference)
        # Merging a grade into a check result.
        base() = Dict{String,Any}("status" => "passed", "verdicts" => ["passed"], "feedback" => Any[])
        fb = Any[Dict("level" => "fail", "title" => "Allocates per call", "detail" => "8 MiB")]
        slow = Dict{String,Any}("status" => "passed", "verdicts" => ["correct", "allocates"], "feedback" => fb,
                                "performance" => Dict("overall" => "needs-work"))
        r = Guided.merge_perf!(base(), s, slow)
        @test r["verdicts"] == ["perf-fail"] && r["status"] == "not-yet"
        @test r["feedback"][1]["title"] == "Performance (`double`): Allocates per call" && r["performance"]["overall"] == "needs-work"
        fast = Dict{String,Any}("status" => "passed", "verdicts" => ["correct", "fast"], "feedback" => Any[])
        @test Guided.merge_perf!(base(), s, fast)["verdicts"] == ["passed"]
        wrong = Dict{String,Any}("status" => "failed", "verdicts" => ["incorrect"], "feedback" => Any[])
        @test "perf-fail" in Guided.merge_perf!(base(), s, wrong)["verdicts"]
        opt = Guided.PerfSpec(s.entry, s.cases, s.args, s.sizes, s.mutates, s.compare, s.rtol, false, s.fail_on)
        r = Guided.merge_perf!(base(), opt, slow)
        @test r["verdicts"] == ["passed"] && r["feedback"][1]["level"] == "warn"   # optional: reported, never blocks
        only_alloc = Guided.PerfSpec(s.entry, s.cases, s.args, s.sizes, s.mutates, s.compare, s.rtol, true, ["slow"])
        @test Guided.merge_perf!(base(), only_alloc, slow)["verdicts"] == ["passed"]   # not in its fail_on
    end

    @testset "question length rule (the course's, per project)" begin
        root = mktempdir()
        mini_project(root)
        q(ch) = "  [[milestone.question]]\n  kind = \"choice\"\n  prompt = \"Which?\"\n  choices = [$(join(repr.(ch), ", "))]\n" *
                "  answer = 1\n  explain = \"Because.\"\n  misconceptions = [\"\", \"No.\", \"No.\"]\n"
        open(joinpath(root, "mini", "project.toml"), "a") do io
            for _ in 1:4
                write(io, q(["the long right answer here", "short", "brief"]))
            end
        end
        probs = Guided.validate(Guided.load_guided("mini"; root))
        @test any(x -> occursin("4 of 4 choice questions the answer is the unique longest", x), probs)
    end

    @testset "deps, show and quiz" begin
        t = Guided.with_deps("name = \"Tidy\"\nuuid = \"8a6e1f6c-0000-4000-8000-000000000000\"\n", "data")
        d = TOML.parse(t)
        @test haskey(d["deps"], "CSV") && haskey(d["deps"], "DataFrames") && d["name"] == "Tidy"
        @test d["targets"]["test"] == ["Test"]
        p = Guided.load_guided("tidy")
        s = Guided.show_milestone(p, 1)
        @test occursin("read_readings(io::IO) -> DataFrame", s) && occursin("[missing-markers]", s)
        @test !occursin("@test", s)                                  # no acceptance test content
        out = IOBuffer()
        right, n = Guided.quiz(p, 1; input = IOBuffer("3\n1\n"), io = out)
        @test (right, n) == (0, 1)
        @test occursin("Not quite: Methods are alternatives", String(take!(out)))
        # The site publishes level 1 only: levels 2 and 3 fade in from `check`.
        sd = Guided.site_data()
        @test all(b -> length(b["hints"]) == 1 && length(b["test_hints"]) <= 1,
                  [b for q in sd["projects"] for m in q["milestones"] for b in m["behaviours"]])
    end

    FAST || @testset "end to end: driver in a fresh process (plain, base env)" begin
        root = mktempdir()
        p = mini_project(root)
        old = Runner.SANDBOX[]
        Runner.SANDBOX[] = :none     # our own fixture code: a plain process is fine
        try
            good = student(root, "good"; src = "module Mini\nexport double\ndouble(x) = x + x\nend\n",
                           test = "using Mini, Test\n@testset \"d\" begin\n    @test double(3) == 6\n    @test_logs double(1)\nend\n")
            r, _ = Guided.check(p, good, 1)
            @test r["verdicts"] == ["passed"]
            # A test file that changes directory, and checks that no sibling
            # implementation is on disk (only its own, plus acceptance/ for the student).
            iso = student(root, "iso"; src = "module Mini\nexport double\ndouble(x) = x + x\nend\n",
                          test = "cd(@__DIR__)\nusing Mini, Test\n@testset \"d\" begin\n    @test double(3) == 6\n    @test_logs double(1)\n" *
                                 "    @test length(readdir(joinpath(@__DIR__, \"..\", \"..\"))) <= 2\n" *
                                 "    @test !isdefined(Main, :GUIDED_JOB) || Main.GUIDED_JOB === nothing\nend\n")
            r, _ = Guided.check(p, iso, 1)
            @test r["verdicts"] == ["passed"]
            weak = student(root, "weak"; src = "module Mini\nexport double\ndouble(x) = x + x\nend\n",
                           test = "using Mini, Test\n@testset \"d\" begin\n    @test double(3) == 6\nend\n")
            r, _ = Guided.check(p, weak, 1)
            @test r["verdicts"] == ["weak-tests"] && r["surviving"] == ["noisy"]
            wrong = student(root, "wrong"; src = "module Mini\nexport double\ndouble(x) = x * x\nend\n",
                            test = "using Mini, Test\n@testset \"d\" begin\n    @test double(2) == 4\nend\n")
            r, _ = Guided.check(p, wrong, 1)
            @test "acceptance-fail" in r["verdicts"] && r["failing"] == ["doubles"]
            broken = student(root, "broken"; src = "module Mini\nexport double\ndouble(x) = 2x\nconst Y = undefined_name\nend\n",
                             test = "using Mini, Test\n@test double(1) == 2\n")
            r, _ = Guided.check(p, broken, 1)
            @test "load-error" in r["verdicts"]
            @test occursin("undefined_name", join([f["detail"] for f in r["feedback"]]))
        finally
            Runner.SANDBOX[] = old
        end
    end
end
