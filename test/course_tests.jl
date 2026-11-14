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
    C(c; units = c.units, requires = c.requires, envs = c.envs, guided = c.guided, outcomes = c.outcomes,
      status = c.status, download = c.download, measured = c.download_measured, note = c.status_note) =
        Course.CourseInfo(c.id, c.title, c.order, status, c.summary, requires, envs, units, c.projects, guided, outcomes,
                          download, measured, note)
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
    # an environment in two courses could not pick one image (Phase 2)
    @test has("environment plots is used by courses science, sciml", swap(4, C(sml; envs = ["base", "plots", "sciml"])))
    @test !any(contains("environment base is used"), Course.validate_courses(courses, units))
    @test has("4 to 8 outcomes", swap(1, C(core; outcomes = core.outcomes[1:3])))
    @test has("is not a unit or project of this course",
              swap(1, C(core; outcomes = [Course.Outcome("x", ["46-sindy"], String[]); core.outcomes[2:end]])))
    @test has("nothing assesses it",
              swap(1, C(core; outcomes = [Course.Outcome("x", String[], String[]); core.outcomes[2:end]])))
    # a download size is shown only with where it was measured; a planned course needs neither
    @test has("[setup] needs download and measured", swap(1, C(core; measured = "")))
    @test has("[setup] needs download and measured", swap(2, C(sci; download = "")))
    @test !has("course core: [setup]", swap(1, C(core; status = "planned", download = "", measured = "")))
    # a course that is not ready says why
    @test has("needs a status_note", swap(4, C(sml; note = "")))
    @test has("needs a status_note", swap(1, C(core; status = "in-progress")))
    @test !isempty(sml.status_note) && isempty(core.status_note)
    # the time estimate is a range from counts at stated rates, and says so
    lo, hi, basis = Course.time_estimate(core, units)
    nready = count(id -> any(u -> u.id == id && u.status == "ready", units), core.units)
    nprob = sum(length(u.problems) for u in units if u.id in core.units && u.status == "ready")
    r = Course.ESTIMATE_RATES
    @test lo == floor(Int, nready * r.unit[1] + nprob * r.problem[1] + length(core.projects) * r.project[1])
    @test hi == ceil(Int, nready * r.unit[2] + nprob * r.problem[2] + length(core.projects) * r.project[2])
    @test 0 < lo < hi
    @test occursin("($nready)", basis) && occursin("($nprob)", basis) && endswith(basis, "not measured")
    # planned units count for nothing: a course of planned units only estimates 0
    planned_only = [Course.Unit(u.id, u.title, u.track, u.env, "planned", u.summary, u.kcs, u.prerequisites,
                                u.outline, u.lessons, u.sections, u.problems) for u in units]
    @test Course.time_estimate(C(core; guided = String[]), planned_only)[1:2] == (floor(Int, length(core.projects) * r.project[1]),
                                                                                  ceil(Int, length(core.projects) * r.project[2]))
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

@testset "predict, then run: the key is read from the recorded output" begin
    Pr(; kc = "k", measure = raw"order (\S+)", choices = ["about 4", "below 3.5"], ranges = [(3.95, Inf), (-Inf, 3.5)],
       values = String[], answer = 2) = Course.Prediction(kc, "What order?", measure, choices, ranges, values, answer, "why")
    E(p; check = true) = Course.Example("println(1)", check, "c", "repl", "", p)
    ok(p; check = true) = Course.prediction_problems(p, E(p; check), ["k"])
    @test ok(Pr()) == String[]
    @test any(contains("not one of the unit's kcs"), ok(Pr(; kc = "other")))
    @test any(contains("check = false"), ok(Pr(); check = false))       # an uncompared output cannot carry a key
    @test any(contains("not a regular expression"), ok(Pr(; measure = "(")))
    @test any(contains("either ranges"), ok(Pr(; values = ["a", "b"])))
    @test any(contains("either ranges"), ok(Pr(; ranges = Tuple{Float64,Float64}[])))
    @test any(contains("one range per choice"), ok(Pr(; ranges = [(0.0, 1.0)])))
    @test any(contains("lo < hi"), ok(Pr(; ranges = [(2.0, 1.0), (3.0, 4.0)])))
    @test any(contains("overlap"), ok(Pr(; ranges = [(0.0, 2.0), (1.0, 3.0)])))
    @test any(contains("index"), ok(Pr(; answer = 3)))

    # half-open ranges: the boundary belongs to the upper choice only
    @test Course.measured_choices(Pr(), "order 2.79\n") == ([2], "2.79")
    @test Course.measured_choices(Pr(), "order 3.95\n") == ([1], "3.95")
    @test Course.measured_choices(Pr(), "order 3.7\n") == (Int[], "3.7")          # in the gap: no choice holds
    @test Course.measured_choices(Pr(), "order NaNx\n") == (Int[], "NaNx")        # not a number
    @test Course.measured_choices(Pr(), "no match\n") == (Int[], nothing)
    @test Course.measured_choices(Pr(; measure = raw"order \S+"), "order 2\n") == (Int[], nothing)   # no capture group
    w = Pr(; ranges = Tuple{Float64,Float64}[], values = ["true", "false"], measure = raw"holds: (\w+)", answer = 1)
    @test Course.measured_choices(w, "holds: TRUE") == ([1], "TRUE")              # words: case-insensitive

    unit(p) = Course.Unit("99-x", "x", "core", "base", "ready", "s", ["k"], String[], String[], String[],
                          [Course.Section("s", "b", [E(p)], Course.Question[])], Course.Problem[])
    rec(out) = Dict("examples" => Dict(Course.example_key("println(1)", "repl") => Dict("output" => out)))
    @test Course.prediction_key_problems(unit(Pr()), rec("order 2.79\n")) == String[]
    @test any(contains("selects choice 1, but the answer is 2"), Course.prediction_key_problems(unit(Pr()), rec("order 4.01\n")))
    @test any(contains("selects 0 choices"), Course.prediction_key_problems(unit(Pr()), rec("order 3.7\n")))
    @test any(contains("does not match"), Course.prediction_key_problems(unit(Pr()), rec("changed\n")))
    @test any(contains("no recorded output"), Course.prediction_key_problems(unit(Pr()), Dict("examples" => Dict())))

    # the course's own predictions, against the outputs recorded in the repository
    units = Course.load_course()
    preds = [(u, e) for u in units for s in u.sections for e in s.examples if e.predict !== nothing]
    @test length(preds) >= 4
    @test all(u -> Course.prediction_key_problems(u, Course.load_outputs(u)) == String[], units)
    @test length(unique(e.predict.kc for (_, e) in preds)) >= 4               # hit rates over several KCs
    site = [e["predict"] for s in SiteData.course_data()["units"] for sec in s["sections"] for e in sec["examples"]
            if haskey(e, "predict")]
    @test length(site) == length(preds) && all(p -> p["measured"] isa String, site)
end

@testset "method-choice checkpoints: scored against the measured work" begin
    rows = [raw"A +calls (\d+) +ok: (?<ok>\w+)", raw"B +calls (\d+) jacs (\d+) +ok: (?<ok>\w+)", raw"C +calls (\d+) +ok: (?<ok>\w+)"]
    Ck(; kc = "k", choices = ["A", "B", "C"], rows = rows, band = 2.0, good = [2], cost = "calls",
       mis = ["slow", "", "inaccurate"]) = Course.Checkpoint(kc, "Which?", choices, rows, cost, band, good, "why", mis)
    E(c; predict = nothing, check = false) = Course.Example("println(1)", check, "c", "repl", "", predict, c)
    bad(c; kw...) = Course.checkpoint_problems(c, E(c; kw...), ["k"])
    @test bad(Ck()) == String[]                       # check = false is allowed: the verdict is checked, not the digits
    @test any(contains("not one of the unit's kcs"), bad(Ck(; kc = "x")))
    @test any(contains("one row regex per choice"), bad(Ck(; rows = rows[1:2])))
    @test any(contains("not a regular expression"), bad(Ck(; rows = ["(", rows[2], rows[3]])))
    @test any(contains("no capture group for the cost"), bad(Ck(; rows = [raw"A ok: (?<ok>\w+)", rows[2], rows[3]])))
    @test any(contains("every choice is good"), bad(Ck(; good = [1, 2, 3])))
    @test any(contains("index choices"), bad(Ck(; good = [4])))
    @test any(contains("no misconception"), bad(Ck(; mis = ["", "", "x"])))
    @test any(contains("band must be"), bad(Ck(; band = 1.0)))
    @test any(contains("no cost label"), bad(Ck(; cost = " ")))
    P = Course.Prediction("k", "p", raw"(\d)", ["a", "b"], [(0.0, 1.0), (1.0, 2.0)], String[], 1, "e")
    @test any(contains("not both"), bad(Ck(); predict = P))

    out = "A calls 900 ok: true\nB calls 100 jacs 20 ok: true\nC calls 50 ok: false\n"
    sc = Course.score_checkpoint(Ck(), out)
    @test sc.costs == [900.0, 120.0, 50.0]             # captures summed; the `ok` group is not a cost
    @test sc.oks == [true, true, false]
    @test sc.verdicts == ["costly", "good", "fails"]   # the cheapest row misses the accuracy: it does not set the bar
    @test sc.ratios[1] ≈ 7.5
    @test Course.checkpoint_output_problems(Ck(), out) == String[]
    @test any(contains("make choice(s) [1, 2] good"), Course.checkpoint_output_problems(Ck(), replace(out, "900" => "200")))
    # 300 / 120 = 2.5: outside the band, but within CHOICE_MARGIN of its edge, so a drift could flip it
    @test any(contains("could flip"), Course.checkpoint_output_problems(Ck(), replace(out, "900" => "300")))
    @test Course.score_checkpoint(Ck(), "nothing here") isa String
    @test Course.score_checkpoint(Ck(), replace(out, "true" => "false")) isa String   # no choice meets the accuracy

    unit(c) = Course.Unit("99-x", "x", "core", "base", "ready", "s", ["k"], String[], String[], String[],
                          [Course.Section("s", "b", [E(c)], Course.Question[])], Course.Problem[])
    rec(o) = Dict("examples" => Dict(Course.example_key("println(1)", "repl") => Dict("output" => o)))
    @test Course.checkpoint_key_problems(unit(Ck()), rec(out)) == String[]
    @test any(contains("no recorded output"), Course.checkpoint_key_problems(unit(Ck()), Dict("examples" => Dict())))

    # the course's own checkpoints, against the outputs recorded in the repository
    units = Course.load_course()
    cks = [e for u in units for s in u.sections for e in s.examples if e.choose !== nothing]
    @test length(cks) >= 3
    @test all(u -> Course.checkpoint_key_problems(u, Course.load_outputs(u)) == String[], units)
    site = [e["choose"] for s in SiteData.course_data()["units"] for sec in s["sections"] for e in sec["examples"]
            if haskey(e, "choose")]
    @test length(site) == length(cks)
    @test all(c -> length(c["costs"]) == length(c["choices"]) == length(c["verdicts"]), site)
end

@testset "break it: the edge is read from the measured sweep" begin
    row = raw"h = (?<p>\S+) +growth (?<m>\S+)"
    B(; kc = "k", row = row, fails = "above", limit = 1.0, edge = (0.2, 0.25), close = 1.5, probe = "h = {{p}}",
      short = "still works", past = "far past") =
        Course.BreakIt(kc, "Find the edge.", "h", "growth", row, fails, limit, edge, close, probe, "why", short, past)
    E(b; check = true, predict = nothing, choose = nothing) = Course.Example("println(1)", check, "c", "repl", "", predict, choose, b)
    bad(b; kw...) = Course.breakit_problems(b, E(b; kw...), ["k"])
    @test bad(B()) == String[]
    @test any(contains("not one of the unit's kcs"), bad(B(; kc = "x")))
    @test any(contains("check = false"), bad(B(); check = false))         # the edge needs a compared output
    P = Course.Prediction("k", "p", raw"(\d)", ["a", "b"], [(0.0, 1.0), (1.0, 2.0)], String[], 1, "e")
    @test any(contains("one of a prediction"), bad(B(); predict = P))
    @test any(contains("not a regular expression"), bad(B(; row = "(")))
    @test any(contains("named groups"), bad(B(; row = raw"h = (\S+) growth (\S+)")))
    @test any(contains("\"above\" or \"below\""), bad(B(; fails = "over")))
    @test any(contains("finite"), bad(B(; limit = NaN)))
    @test any(contains("0 < low < high"), bad(B(; edge = (0.3, 0.2))))
    @test any(contains("0 < low < high"), bad(B(; edge = (NaN, NaN))))       # what a malformed `edge` loads as
    @test any(contains("wider than close"), bad(B(; edge = (0.1, 0.25))))
    @test any(contains("close must be"), bad(B(; close = 3.0)))
    @test any(contains("{{p}}"), bad(B(; probe = "h = 0.2")))
    @test any(contains("no short"), bad(B(; short = " ")))

    # rows are matched line by line and sorted by the parameter; NaN counts as failed
    out = "h = 0.3  growth 9.0\nh = 0.1  growth 0.01\nh = 0.25  growth 1.5\nh = 0.2  growth 0.9\nh = 0.5  growth NaN\n"
    sc = Course.score_breakit(B(), out)
    @test sc.ps == [0.1, 0.2, 0.25, 0.3, 0.5]
    @test sc.failed == [false, false, true, true, true]
    @test sc.edge == (0.2, 0.25) && sc.side == "high"
    @test Course.breakit_output_problems(B(), out) == String[]
    @test any(contains("but edge = [0.2, 0.3]"), Course.breakit_output_problems(B(; edge = (0.2, 0.3), close = 1.6), out))
    low = Course.score_breakit(B(; fails = "below", limit = 1.0), replace(out, "h = 0.5  growth NaN\n" => ""))  # the low side fails
    @test low.side == "low" && low.edge == (0.2, 0.25)
    @test contains(Course.score_breakit(B(), "h = 0.1  growth 0.5\nh = 0.2  growth 2\nh = 0.3  growth 0.5\nh = 0.4  growth 2\n"),
                   "3 times")                                            # no single edge
    @test contains(Course.score_breakit(B(), "h = 0.1  growth 0.5\nh = 0.2  growth 0.5\nh = 0.3  growth 0.5\nh = 0.4  growth 0.5\n"),
                   "works at every")
    @test contains(Course.score_breakit(B(), "h = 0.1  growth 0.5\nh = 0.2  growth 2\n"), "at least")
    @test contains(Course.score_breakit(B(), replace(out, "growth 9.0" => "growth fast")), "not a number")
    @test contains(Course.score_breakit(B(), out * "h = 0.1  growth 0.02\n"), "swept twice")

    # the probe: one row at each end of the edge, agreeing with the sweep
    @test Course.probe_code(B(), 0.25) == "h = 0.25"
    @test Course.probe_problems(B(), "high", "h = 0.2  growth 0.9\n", "h = 0.25  growth 1.5\n") == String[]
    @test any(contains("works, but the sweep says it fails"),
              Course.probe_problems(B(), "high", "h = 0.2  growth 0.9\n", "h = 0.25  growth 0.95\n"))
    @test any(contains("(one is needed)"), Course.probe_problems(B(), "high", "", "h = 0.25  growth 1.5\n"))

    unit(b) = Course.Unit("99-x", "x", "core", "base", "ready", "s", ["k"], String[], String[], String[],
                          [Course.Section("s", "b", [E(b)], Course.Question[])], Course.Problem[])
    rec(o) = Dict("examples" => Dict(Course.example_key("println(1)", "repl") => Dict("output" => o)))
    @test Course.breakit_key_problems(unit(B()), rec(out)) == String[]
    @test any(contains("no recorded output"), Course.breakit_key_problems(unit(B()), Dict("examples" => Dict())))

    # the course's own challenges, against the outputs recorded in the repository
    units = Course.load_course()
    bks = [e for u in units for s in u.sections for e in s.examples if e.breakit !== nothing]
    @test length(bks) >= 3
    @test all(u -> Course.breakit_key_problems(u, Course.load_outputs(u)) == String[], units)
    @test length(unique(e.breakit.kc for e in bks)) >= 3                      # stability, convergence, identifiability
    site = [e["breakit"] for s in SiteData.course_data()["units"] for sec in s["sections"] for e in sec["examples"]
            if haskey(e, "breakit")]
    @test length(site) == length(bks)
    @test all(b -> count(r -> r["failed"], b["rows"]) in 1:length(b["rows"])-1, site)
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

@testset "find the bug: one planted line, measured by the convergence tests" begin
    ref = "function f(h)\n    a = h / 2\n    return a + 1\nend\n"
    T(; name = "order", row = raw"^order: (?<m>\S+)$", expect = (1.8, 2.2), explain = "what the slope measures") =
        Course.BugTest(name, "println(\"order: \", f(1.0))", row, expect, explain)
    Bg(; kc = "k", find = "a = h / 2", replace = "a = h", tests = [T()], mis = "the belief", tokens = ["h / 2"]) =
        Course.Bug(kc, find, replace, tests, mis, tokens)
    Pb(b; hints = ["look at the scale"], starter = something(Course.plant(ref, b), "")) =
        Course.Problem("p", "t", "core", ["k"], "", "f", starter, ref, ["1.0"], "", "isequal", "", 1e-8, true, false,
                       hints, nothing, Course.Variant[], 1, 1, String[], b)
    probs(b; kw...) = Course.bug_problems(Pb(b; kw...), ["k"])

    # the starter is generated: the reference with exactly one line changed
    @test Course.plant(ref, Bg()) == replace(ref, "a = h / 2" => "a = h")
    @test Course.plant(ref, Bg(find = "nowhere")) === nothing
    @test Course.plant(ref, Bg(find = "h")) === nothing                       # occurs more than once
    @test Course.changed_lines(ref, Course.plant(ref, Bg())) == [2]
    @test isempty(probs(Bg()))
    @test any(contains("exactly once"), probs(Bg(find = "nowhere")))
    @test any(contains("exactly one line"), probs(Bg(find = "a = h / 2\n    return a + 1", replace = "a = h\n    return a")))
    @test any(contains("nothing is planted"), probs(Bg(replace = "a = h / 2")))
    @test any(contains("remove `starter`"), probs(Bg(); starter = Course.BUG_STARTER_GIVEN))
    @test any(contains("not one of the unit's KCs"), probs(Bg(kc = "other")))
    @test any(contains("no misconception"), probs(Bg(mis = "")))
    @test any(contains("no hints"), probs(Bg(); hints = String[]))
    @test any(contains("no convergence tests"), probs(Bg(tests = Course.BugTest[])))

    # answer tokens: part of the fix, absent from the planted line and from the level-1 feedback
    @test any(contains("not part of the fix"), probs(Bg(tokens = ["h * 2"])))
    @test any(contains("also appears in the planted line"), probs(Bg(tokens = ["a = h"])))
    @test any(contains("first hint contains"), probs(Bg(); hints = ["try h / 2"]))
    @test any(contains("explain contains"), probs(Bg(tests = [T(explain = "compare with h / 2")])))
    @test any(contains("name contains"), probs(Bg(tests = [T(name = "h / 2 test")])))
    @test isempty(probs(Bg(); hints = ["scale first", "then h / 2"]))          # later hints may be specific

    # the tests themselves
    @test any(contains("named group `m`"), probs(Bg(tests = [T(row = raw"order: (\S+)")])))
    @test any(contains("not a valid regex"), probs(Bg(tests = [T(row = "order: (")])))
    @test any(contains("two finite numbers"), probs(Bg(tests = [T(expect = (2.2, 1.8))])))
    @test any(contains("two finite numbers"), probs(Bg(tests = [T(expect = (NaN, NaN))])))
    @test any(contains("duplicate name"), probs(Bg(tests = [T(), T()])))

    # reading a test's one line, and its verdict
    t = T()
    @test Course.bug_test_value(t, "f (generic function with 1 method)\norder: 2.01\n") == 2.01
    @test Course.bug_test_value(t, "order: 2.0\norder: 2.1\n") === nothing        # two lines: no reading
    @test Course.bug_test_value(t, "ERROR: UndefVarError\n") === nothing
    @test isinf(Course.bug_test_value(t, "order: Inf"))
    @test Course.bug_test_passes(t, 2.01) && Course.bug_test_passes(t, 1.8)
    @test !Course.bug_test_passes(t, 1.0) && !Course.bug_test_passes(t, nothing) && !Course.bug_test_passes(t, NaN)
    @test Course.bug_test_code("f(h) = h\n\n", t) == "f(h) = h\n\nprintln(\"order: \", f(1.0))"

    # loading: a hand-written starter is refused, a generated one is the planted reference
    d = Dict("id" => "p", "title" => "t", "difficulty" => "core", "prompt" => "", "entry" => "f", "reference" => ref,
             "bug" => Dict("kc" => "k", "find" => "a = h / 2", "replace" => "a = h", "misconception" => "m",
                           "answer_tokens" => ["h / 2"],
                           "test" => [Dict("name" => "n", "code" => "c", "row" => "(?<m>x)", "expect" => [1, 2], "explain" => "e")]))
    p = Course.load_problem(d)
    @test p.starter == Course.plant(ref, p.bug) && p.bug.tests[1].expect == (1.0, 2.0)
    @test Course.load_problem(merge(d, Dict("starter" => "f(h) = h"))).starter == Course.BUG_STARTER_GIVEN
    @test Course.load_problem(merge(d, Dict("bug" => merge(d["bug"], Dict("test" => [Dict("expect" => [1])]))))).bug.tests[1].expect |>
          x -> all(isnan, x)

    # the course's find-the-bug problems are valid, and the site carries them only on those problems
    units = Course.load_course()
    bugs = [p for u in units for p in u.problems if p.bug !== nothing]
    @test length(bugs) >= 3
    for u in units, p in u.problems
        p.bug === nothing || @test isempty(Course.bug_problems(p, u.kcs))
    end
    site = [p for u in SiteData.course_data()["units"] for p in u["problems"]]
    @test count(p -> haskey(p, "bug"), site) == length(bugs)
    for p in filter(p -> haskey(p, "bug"), site)
        @test occursin(p["bug"]["planted"], p["starter"]) && !occursin(p["bug"]["fixed"], p["starter"])
    end
end

@testset "Parsons problems: every arrangement measured, distractors never work" begin
    ref = """
    function f(x)
        s = 0
        for v in x
            s += v
        end
        return s
    end
    """
    dz(ds...) = Course.Parsons("k", 1, 2, collect(Course.Distractor, ds))
    good = Course.Distractor("    s = 1", 1, "starts the sum at one")
    Pz(z; reference = ref, compare = "isequal", gen = "", cases = ["[1, 2]", "Int[]"], starter = Course.parsons_starter(reference, z)) =
        Course.Problem("p", "t", "core", ["k"], "", "f", starter, reference, cases, gen, compare,
                       compare == "custom" ? "(a, b) -> a == b" : "", 1e-8, true, false, ["h"], nothing, Course.Variant[], 1, 1,
                       String[], nothing, z)
    probs(z; kw...) = Course.parsons_problems(Pz(z; kw...), ["k"])

    # lines: fixed head and tail, movable lines in working order, then the distractors
    p = Pz(dz(good))
    l = Course.parsons_lines(p)
    @test l.head == ["function f(x)"] && l.tail == ["    return s", "end"]
    @test l.items == ["    s = 0", "    for v in x", "        s += v", "    end"]
    @test Course.parsons_pool(p) == [l.items; "    s = 1"]
    @test p.starter == "function f(x)\n    # put the lines here, in order\n    return s\nend\n"
    @test isempty(probs(dz(good)))

    # indentation is read as block structure, 4 spaces per level
    @test Course.parsons_depth(1, "    for i in 1:n") == 2
    @test Course.parsons_depth(2, "        x += 1") == 2
    @test Course.parsons_depth(2, "    end") == 1
    @test Course.parsons_depth(2, "    x += 1") == -1          # under-indented inside the loop
    @test Course.parsons_depth(1, "        end") == -1         # an `end` at the wrong level
    @test Course.parsons_depth(2, "    else") == 2 && Course.parsons_depth(1, "    if a") == 2
    @test Course.parsons_depth(1, "    map(x) do v") == 2      # a do block opens
    @test Course.parsons_depth(-1, "    x") == -1
    @test Course.parsons_depth(0, ["function f(x)", "    s = 0", "    return s", "end"]) == 0

    # structural problems
    has(z, s; kw...) = any(m -> occursin(s, m), probs(z; kw...))
    @test has(Course.Parsons("other", 1, 2, [good]), "kc 'other'")
    @test has(Course.Parsons("k", 0, 2, [good]), "head and tail")
    @test has(Course.Parsons("k", 1, 2, [good]), "starter is generated"; starter = Course.PARSONS_STARTER_GIVEN)
    @test has(dz(good), "compare must be"; compare = "custom")
    @test has(dz(good), "gen is not used"; gen = "rng -> [([1],)]")
    @test has(dz(good), "two explicit cases"; cases = ["[1]"])
    @test has(dz(Course.Distractor("        s = 1", 1, "m")), "indent it like the line it replaces (4 spaces)")
    @test has(dz(Course.Distractor("    s = 0", 1, "m")), "the same text as a movable line")
    @test has(dz(Course.Distractor("    s = 1", 9, "m")), "replaces must be 1 to 4")
    @test has(dz(Course.Distractor("    s = 1", 1, " ")), "no misconception")
    @test has(dz(good, Course.Distractor("    s = 2", 1, "m")), "two distractors replace the same line")
    @test has(dz(good, good), "duplicate line")
    @test has(dz(good), "`while`"; reference = replace(ref, "for v in x" => "while v in x"))
    @test has(dz(good), "not indented 4 spaces"; reference = replace(ref, "        s += v" => "      s += v"))
    @test has(dz(good), "blank"; reference = replace(ref, "    s = 0\n" => "    s = 0\n\n"))
    @test has(dz(good), "3 to 8 movable lines"; reference = "function f(x)\n    s = 0\n    return s\nend\n")
    @test has(Course.Parsons("k", 0, 1, [good]), "head must open the function")

    # loading: the starter is generated, a hand-written one is refused
    d = Dict("id" => "p", "title" => "t", "difficulty" => "core", "prompt" => "", "entry" => "f", "reference" => ref,
             "parsons" => Dict("kc" => "k", "head" => 1, "tail" => 2,
                               "distractor" => [Dict("line" => "    s = 1", "replaces" => 1, "misconception" => "m")]))
    q = Course.load_problem(d)
    @test q.starter == Course.parsons_starter(ref, q.parsons) && q.parsons.distractors[1].replaces == 1
    @test Course.load_problem(merge(d, Dict("starter" => "f(x) = 0"))).starter == Course.PARSONS_STARTER_GIVEN

    # the recorder's output: nothing unless it finished
    @test Course.parse_parsons_output("accepted: 1 2\n") === nothing
    @test Course.parse_parsons_output("accepted: 2 1 3\naccepted: 1 2 3\nparsons: 7 run\n") == ["1 2 3", "2 1 3"]

    # feedback, in order: invalid, distractor, count, solved, longest working prefix
    # (web/src/parsons.test.ts checks the same vectors)
    pool = ["a", "b", "end", "end", "x"]
    acc = ["1 2 3 3", "2 1 3 3"]
    fb(o) = (r = Course.parsons_feedback(pool, 4, acc, o); (r.kind, r.value))
    @test fb([1, 1, 3, 4]) == (:invalid, 0) && fb([1, 2, 3, 6]) == (:invalid, 0)
    @test fb([1, 5, 3, 4]) == (:distractor, 1)
    @test fb([1, 2, 3]) == (:count, 4)
    @test fb([2, 1, 4, 3]) == (:solved, 4)                   # the two `end` lines are interchangeable
    @test fb([1, 3, 2, 4]) == (:prefix, 1) && fb([3, 1, 2, 4]) == (:prefix, 0)
    @test Course.parsons_key(pool, [2, 1, 4, 3]) == "2 1 3 3"

    # the display order is a permutation that does not change between runs
    o = Course.parsons_display_order("p", pool)
    @test sort(o) == 1:5 && o == Course.parsons_display_order("p", pool)

    # verify's checks on the measured set
    u = Course.Unit("u", "t", "core", "base", "ready", "", ["k"], String[], String[], String[], Course.Section[], [p])
    rp(stored, now) = Practice.parsons_record_problems(u, stored, now)
    ok = Dict("p" => ["1 2 3 4"])
    @test isempty(rp(ok, ok))
    @test any(m -> occursin("own order is not", m), rp(Dict("p" => ["2 1 3 4"]), Dict("p" => ["2 1 3 4"])))
    @test any(m -> occursin("distractor 1", m), rp(Dict("p" => ["1 2 3 4", "5 2 3 4"]), Dict("p" => ["1 2 3 4", "5 2 3 4"])))
    @test any(m -> occursin("changed", m), rp(Dict("p" => ["1 2 3 4", "2 1 3 4"]), ok))
    @test any(m -> occursin("no measured", m), rp(ok, nothing))
    @test any(m -> occursin("stale", m), rp(Dict("p" => ["1 2 3 4"], "q" => ["1"]), ok))

    # the course's Parsons problems are valid, measured, and on the site with their accepted sets
    units = Course.load_course()
    zs = [(u, p) for u in units for p in u.problems if p.parsons !== nothing]
    @test length(zs) >= 3
    for (u, p) in zs
        @test isempty(Course.parsons_problems(p, u.kcs))
        acc = Course.load_outputs(u)["parsons"][p.id]
        @test isempty(Practice.parsons_record_problems(u, Course.load_outputs(u)["parsons"], Course.load_outputs(u)["parsons"]))
        @test join(1:length(Course.parsons_lines(p).items), " ") in acc
    end
    site = [p for u in SiteData.course_data()["units"] for p in u["problems"]]
    @test count(p -> haskey(p, "parsons"), site) == length(zs)
    for (u, p) in zs
        s = only(filter(x -> x["id"] == p.id, site))["parsons"]
        @test s["accepted"] == [Base.parse.(Int, split(a)) for a in Course.load_outputs(u)["parsons"][p.id]]
        @test s["pool"] == Course.parsons_pool(p) && s["n"] == length(Course.parsons_lines(p).items)
    end

    # the enumeration itself, in a fresh process: the two `s` lines commute only with
    # the right indentation, and the distractor (sum starts at one) is never accepted
    if !FAST
        refm = """
        function f(x)
            s = 0
            n = 0
            for v in x
                s += v
                n += 1
            end
            return s - n
        end
        """
        zm = Course.Parsons("k", 1, 2, [Course.Distractor("    s = 1", 1, "starts at one")])
        pm = Pz(zm; reference = refm, cases = ["[1, 2, 3]", "[5]"])
        um = Course.Unit("u", "t", "core", "base", "ready", "", ["k"], String[], String[], String[], Course.Section[], [pm])
        acc = Practice.parsons_accepted(pm, um)
        # s = 0 / n = 0 in either order, and s += v / n += 1 in either order: 4 orders
        @test acc == ["1 2 3 4 5 6", "1 2 3 5 4 6", "2 1 3 4 5 6", "2 1 3 5 4 6"]
    end
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
    mem = Runner.image_memory("science")
    @test "--pids-limit=$(Runner.CONTAINER_PIDS)" in a && "--memory=$mem" in a
    @test "--memory-swap=$mem" in a                                   # no swap beyond the memory limit
    @test "--heap-size-hint=$(Runner.heap_hint(mem))" in a              # GC collects before the kernel kills
    @test Runner.heap_hint("6g") == "4G" == Runner.CONTAINER_HEAP_HINT && Runner.heap_hint("3g") == "2G"
    @test Runner.heap_hint("2g") == "1G"
    # Measured per image (Phase 2): every image has its own limit, at least 2 GB.
    @test sort!(collect(keys(Runner.IMAGE_MEMORY))) == sort(Runner.images())
    @test all(m -> Base.parse(Int, chop(m)) >= 2, values(Runner.IMAGE_MEMORY))
    b = Runner.docker_args(; project_env = "base", threads = 1, name = "julia-tutor-x")
    @test "--memory=2g" in b && "--memory-swap=2g" in b && "--heap-size-hint=1G" in b
    # The environment picks the image; every other flag is the same in every
    # image (the Sandbox/security engineer reviews this list, Phase 2).
    @test Runner.image_name("science") in a && Runner.env_image("data") == "science"
    strip_img(x) = filter(f -> !(f in Runner.image_name.(Runner.images())) && !startswith(f, "--memory") &&
                               !startswith(f, "--heap-size-hint") && !startswith(f, "--project="), x)
    for e in ("base", "scicomp", "mtk", "sciml", "plots")
        b = Runner.docker_args(; project_env = e, threads = 4, name = "julia-tutor-x")
        @test strip_img(b) == strip_img(a)
        @test Runner.image_name(Runner.env_image(e)) in b
    end
    @test Runner.env_image("base") == "base" && Runner.env_image("mtk") == "scicomp" && Runner.env_image("sciml") == "sciml"
    @test_throws ErrorException Runner.env_image("nope")
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

    # the memory peak comes after the files block only, so printing the prefix
    # does not cut the learner's output
    peakline = Runner.PEAK_PREFIX * "123456 cgroup\n"
    o, n = Runner.split_peak(out * peakline)
    @test n == (123456, "cgroup") && o == out
    @test Runner.split_peak(out * Runner.PEAK_PREFIX * "77 maxrss\n")[2] == (77, "maxrss")
    @test Runner.split_peak(out * Runner.PEAK_PREFIX * "77 lies\n") == (out, nothing)
    let saved = copy(Runner.MEMORY_PEAKS)
        empty!(Runner.MEMORY_PEAKS)
        Runner.note_peak!("x", (5, "cgroup")); Runner.note_peak!("x", (3, "cgroup")); Runner.note_peak!("x", nothing)
        @test Runner.MEMORY_PEAKS["x"] == (5, "cgroup")
        empty!(Runner.MEMORY_PEAKS); merge!(Runner.MEMORY_PEAKS, saved)
    end
    fake = "a\n" * Runner.PEAK_PREFIX * "9\nb\n" * out
    @test Runner.split_peak(fake) == (fake, nothing)
    @test Runner.split_peak("crashed\n" * peakline) == ("crashed\n" * peakline, nothing)

    # one image per course with environments of its own; Core Julia runs in base
    ie = Runner.image_envs()
    courses = Course.load_courses()
    @test Runner.images() == ["base", "scicomp", "science", "sciml"]                  # base, then by name
    @test Runner.course_image("core") == "base" && Runner.image_course("base") == "core"
    for c in courses
        @test ie[Runner.course_image(c.id)] == sort(filter(!=("base"), c.envs))
    end
    # every environment is in exactly one image (base: in the base image)
    all_envs = sort!(readdir(joinpath(Course.COURSE_DIR, "envs")))
    @test sort!(["base"; reduce(vcat, values(ie))]) == all_envs
    # each image's label covers its Dockerfiles, the child scripts and its environments only
    names = first.(Runner.sandbox_inputs("science"))
    @test "child/sandbox.jl" in names && "child/contained.jl" in names && "envs/data/Manifest.toml" in names
    @test "base.Dockerfile" in names && "science.Dockerfile" in names && !any(startswith("envs/sciml/"), names)
    @test !any(startswith("envs/data/"), first.(Runner.sandbox_inputs("base")))
    @test all(length(Runner.sandbox_hash(i)) == 64 for i in Runner.images())
    @test allunique(Runner.sandbox_hash.(Runner.images()))
    # each course Dockerfile installs exactly its course's environments, one layer each
    dfs = Dict(i => replace(read(joinpath(Runner.SANDBOX_DIR, "$i.Dockerfile"), String), "\r\n" => "\n") for i in Runner.images())
    for (img, envs) in ie, e in all_envs
        copied = occursin("COPY envs/$e /tutor/envs/$e\n", dfs[img])
        @test copied == (e in envs || (img == "base" && e == "base"))
        copied && isfile(joinpath(Course.COURSE_DIR, "envs", e, "Manifest.toml")) && @test occursin("/tutor/envs/$e && rm", dfs[img])
    end
    @test occursin(r"^FROM julia:1\.10\.13@sha256:[0-9a-f]{64} AS runtime$"m, dfs["base"])
    for img in Runner.images()
        img == "base" && continue
        @test occursin("ARG RUNTIME\nFROM \${RUNTIME}\n", dfs[img])      # built on base's runtime stage
        @test endswith(dfs[img], "COPY child /tutor/child\nUSER 1000:1000\nWORKDIR /tmp\n")
    end
    @test endswith(dfs["base"], "COPY child /tutor/child\nUSER 1000:1000\nWORKDIR /tmp\n")
    # Package caches are compiled for a fixed list of CPUs, not the build
    # machine's: every precompile step reads it (a cache built on one CI
    # runner was rejected on the next, CI run 42998692738).
    @test occursin("> /tutor/cpu-target\n", dfs["base"])
    for img in Runner.images()
        for line in filter(l -> occursin("Pkg.precompile()", l), split(dfs[img], '\n'))
            @test occursin("export JULIA_CPU_TARGET=\"\$(cat /tutor/cpu-target)\" && julia", line)
        end
    end
    # nothing in any image is fetched at run time (the container has no network)
    @test !any(df -> occursin(r"\b(ADD|VOLUME|EXPOSE)\b", df), values(dfs))

    # published images are pulled by digest, and only for these inputs
    h = Runner.sandbox_hash("sciml"); dg = "sha256:" * "ab"^32
    rec = Dict("sciml" => Dict("inputs" => h, "digest" => dg))
    @test Runner.published_ref("sciml"; record = rec, hash = h) == ("$(Runner.REGISTRY)/julia-tutor-sandbox-sciml@$dg", nothing)
    ref, why = Runner.published_ref("sciml"; record = rec, hash = "0"^64)
    @test ref === nothing && occursin("tutor sandbox build sciml", why)
    @test Runner.published_ref("base"; record = rec)[1] === nothing                   # nothing recorded
    bad = Dict("sciml" => Dict("inputs" => h, "digest" => "latest; rm -rf /"))
    @test Runner.published_ref("sciml"; record = bad, hash = h)[1] === nothing         # digests only
    @test Runner.registry_tag("sciml", h) == "$(Runner.REGISTRY)/julia-tutor-sandbox-sciml:$(VERSION)-$(h[1:16])"
    t = Runner.images_toml(Dict("base" => dg, "sciml" => dg))
    parsed = TOML.parse(t)
    @test sort!(collect(keys(parsed))) == ["base", "sciml"] && parsed["base"]["inputs"] == Runner.sandbox_hash("base")
    @test Runner.published_ref("sciml"; record = parsed)[1] !== nothing
    # the committed file, when there is one, is well formed
    for (img, r) in Runner.published()
        @test img in Runner.images() && Runner.valid_digest(r["digest"]) && length(r["inputs"]) == 64
    end
    @test Runner.manifest_bytes(Dict("layers" => [Dict("size" => 10), Dict("size" => 5)], "config" => Dict("size" => 1))) == 16
    @test Runner.manifest_bytes(Dict("manifests" => [])) === nothing
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

    # `tutor serve --course=core`: the same policy in front, then only Core's
    # environments and problems, each refusal naming the course to restart with
    ccfg = Server.ServerConfig(; port = 8765, token = tok, units = Course.load_course(), course = "core")
    creq(m, path; body = "") = Server.handle(ccfg,
        Server.Request(m, path, Dict("host" => "127.0.0.1:8765", "authorization" => "Bearer $tok"), body);
        run = fake_run, gradefn = fake_grade)
    h = JSON.parse_json(creq("GET", "/api/health").body)
    @test h["envs"] == ["base"] && h["course"] == "core"
    @test JSON.parse_json(req("GET", "/api/health"; h = auth).body)["course"] == ""
    n = length(ran)
    @test creq("POST", "/api/run"; body = "{\"code\": \"1+2\"}").status == 200 && length(ran) == n + 1
    r = creq("POST", "/api/run"; body = "{\"code\": \"x\", \"env\": \"sciml\"}")
    @test r.status == 403 && occursin("--course=sciml", JSON.parse_json(r.body)["error"]) && length(ran) == n + 1
    @test creq("POST", "/api/run"; body = "{\"code\": \"x\", \"env\": \"nope\"}").status == 400
    @test creq("POST", "/api/grade"; body = "{\"code\": \"x\", \"problem\": \"fahrenheit\"}").status == 200
    _, sp = Course.find_problem(Course.load_course(), "sparse-jacobi-pcg")
    r = creq("POST", "/api/grade"; body = "{\"code\": \"x\", \"problem\": \"$(sp.id)\"}")
    @test r.status == 403 && occursin("--course=scicomp", JSON.parse_json(r.body)["error"])
    @test Server.handle(ccfg, Server.Request("POST", "/api/run", Dict("host" => "127.0.0.1:8765"), "{\"code\": \"1\"}");
                        run = fake_run).status == 401                                 # the token still comes first
    scfg = Server.ServerConfig(; port = 8765, token = tok, units = Course.load_course(), course = "scicomp")
    @test Server.served_envs(scfg) == ["base", "mtk", "scicomp"]

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

    # The same child in the container, when Docker and an up-to-date base image
    # are here (everything below is Core Julia's: base env, core problems).
    why = Runner.sandbox_problem(["base"])
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
                # the container reports its memory peak (cgroup, or Julia's RSS on older kernels)
                @test haskey(Runner.MEMORY_PEAKS, "base") && Runner.MEMORY_PEAKS["base"][1] > 100 * 2^20
                # output that imitates the peak line is the learner's, kept whole
                r = Practice.run_code("println(\"$(Runner.PEAK_PREFIX)1 cgroup\"); println(\"after\")")
                @test r.output == "$(Runner.PEAK_PREFIX)1 cgroup\nafter\n"
            finally
                Runner.SANDBOX[] = :none
            end
        end
    else
        @info "skipping the container tests: $why"
    end
end
