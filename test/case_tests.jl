# Tests for scientific case projects (src/cases.jl). Pure: no study runs,
# no subprocess. `tutor case verify` runs the student-code side.

using JuliaTutor: Cases

spec(; kind = "number", words = String[], min_digits = 2, rtol = 0.0, atol = 0.0) =
    Cases.ClaimSpec("x", "method", kind, words, min_digits, rtol, atol, "", "")

# The values a report claims, read back from its own tags: a report checked
# against these must have no value findings, so the fixtures can be tested
# without running the study.
function written_values(c, text)
    out = Dict{String,Any}()
    for t in Cases.parse_report(text).tags
        t.kind === :claim && t.value !== nothing || continue
        s = Cases.claim(c, t.id)
        s === nothing && continue
        out[t.id] = s.kind == "word" ? t.value :
                    Cases.is_integer_literal(t.value) ? Base.parse(Int, t.value) : Base.parse(Float64, t.value)
    end
    return out
end

@testset "cases" begin
    @testset "match_value: half a unit in the last written digit" begin
        @test Cases.match_value(spec(), "5.18", 5.18293)[1] === nothing
        @test Cases.match_value(spec(), "5.19", 5.18293)[1] == "claim-mismatch"
        @test Cases.match_value(spec(), "5.185", 5.18293)[1] == "claim-mismatch"    # more digits, tighter
        @test Cases.match_value(spec(min_digits = 3), "5.2", 5.18293)[1] == "claim-too-coarse"
        @test Cases.match_value(spec(min_digits = 3), "0.5", 0.5)[1] === nothing     # exact beats min_digits
        @test Cases.match_value(spec(), "1e-6", 1.0e-6)[1] === nothing
        @test Cases.match_value(spec(), "3.16e-9", 3.1622776601683795e-9)[1] === nothing
        @test Cases.match_value(spec(), "506498", 506498)[1] === nothing
        @test Cases.match_value(spec(), "506500", 506498)[1] == "claim-mismatch"     # integers are exact
        @test Cases.match_value(spec(rtol = 0.01), "20.0", 20.15)[1] === nothing
        @test Cases.match_value(spec(), "abc", 1.0)[1] == "claim-no-value"
        w = spec(kind = "word", words = ["dp54", "verlet"])
        @test Cases.match_value(w, "DP54", "dp54")[1] === nothing
        @test Cases.match_value(w, "verlet", "dp54")[1] == "claim-mismatch"
        @test Cases.match_value(w, "rk4", "dp54")[1] == "claim-mismatch"
        @test Cases.written_precision("5.18") == (3, -2)
        @test Cases.written_precision("3.9e-3") == (2, -4)
        @test Cases.written_precision("1000") == (4, 0)
    end

    @testset "parse_report: sections, tags, what is not a claim" begin
        text = """
        ---
        title: "x {claim:yaml}"
        ---
        <!-- 1.0{claim:comment}
        spans lines -->
        ## Method choice: which one
        The order is 5.18{claim:a} and the word dp54 {claim:b}.
        Inline `2.0`{claim:c}.

        ```julia
        3.0{claim:fenced}
        ```
        ## Something else
        4.0{claim:d}
        """
        r = Cases.parse_report(text)
        @test r.sections == [("method", 6)]
        ids = [t.id for t in r.tags]
        @test ids == ["a", "b", "c", "d"]
        a, b, c_, d = r.tags
        @test (a.value, a.line, a.step) == ("5.18", 7, "method")
        @test b.value == "dp54"                       # one space before the tag is allowed
        @test c_.value === nothing                    # inline code is no value
        @test d.step === nothing                      # not under a method-step heading
        @test a.paragraph == c_.paragraph != d.paragraph
    end

    c = Cases.load_case("odeint")
    @testset "the odeint brief is valid" begin
        @test isempty(Cases.validate_case(c))
        @test length(c.milestones) == 3 && count(m -> m.report, c.milestones) == 1
        @test Set(c.emphasised) <= Set(Cases.STEP_IDS)
        @test all(e -> all(id -> Cases.claim(c, id) !== nothing, e.claims), c.evidence)
    end

    @testset "the claim checker on the reference report and its fixtures" begin
        text = replace(read(Cases.reference_report(c), String), "\r\n" => "\n")
        vals = written_values(c, text)
        @test length(vals) == length(c.claims)
        fs, est = Cases.check_report(c, text, vals; rerun = vals)
        @test isempty(fs)
        @test only(est)[1:3] == ("verlet_nper", "10000", "nper_verlet")
        fx = Cases.report_fixtures(c)
        @test length(fx) >= 10
        for (name, t, differs, want) in fx
            rr = copy(vals)
            isempty(differs) || (rr[differs] = vals[differs] isa AbstractFloat ? nextfloat(vals[differs]) : "changed")
            got = sort!(unique([f.code for f in Cases.check_report(c, t, vals; rerun = rr)[1]]))
            @test (name, got) == (name, want)
        end
        # A wrong study value (not a wrong report) is a mismatch too: the report
        # must agree with what the code computed, whatever the code computed.
        bad = copy(vals); bad["conv_order"] = 4.0
        @test "claim-mismatch" in [f.code for f in Cases.check_report(c, text, bad)[1]]
    end

    @testset "brief, start files and site page are generated from case.toml" begin
        md = Cases.brief_markdown(c)
        @test occursin("No program grades the reasoning", md)
        @test occursin("| `conv_order` |", md)
        @test !occursin("## Rubric", Cases.brief_markdown(c; rubric = false))
        files = Cases.start_files(c)
        @test haskey(files, "study/study.jl") && haskey(files, "report.qmd") && haskey(files, "BRIEF.md")
        @test occursin("case = \"odeint\"", files[".tutor-case.toml"])
        @test !any(k -> startswith(k, "case/") || occursin("acceptance", k), keys(files))   # hidden tests stay hidden
        @test occursin("error(\"TODO: study\")", files["study/study.jl"])                  # the template, not the reference
        path = Cases.site_page_path(c)
        @test isfile(path)
        @test replace(read(path, String), "\r\n" => "\n") == Cases.site_page(c)    # `tutor case site` was run
        @test occursin("tutor case estimate <dir> verlet_nper <value>", md)       # the brief says how to commit
        @test occursin("before your first `tutor case check <dir> 3`", md)
    end

    @testset "estimate before you compute" begin
        CE = Cases.CommittedEstimate
        none = CE[]
        # refusals: unknown id, not a number, zero, no reason, multi-line, too long, already committed
        @test occursin("no estimate `nope`", Cases.estimate_problem(c, "nope", "10", "r", none))
        @test occursin("not a number", Cases.estimate_problem(c, "verlet_nper", "lots", "r", none))
        @test occursin("not a number", Cases.estimate_problem(c, "verlet_nper", "Inf", "r", none))
        @test occursin("0 cannot", Cases.estimate_problem(c, "verlet_nper", "0", "r", none))
        @test occursin("without its reasoning", Cases.estimate_problem(c, "verlet_nper", "1e4", "  ", none))
        @test occursin("one line", Cases.estimate_problem(c, "verlet_nper", "1e4", "a\nb", none))
        @test occursin("longer than", Cases.estimate_problem(c, "verlet_nper", "1e4", "x"^301, none))
        done = [CE("verlet_nper", "1e4", 1e4, "order 2 from one run", 0)]
        @test occursin("already committed", Cases.estimate_problem(c, "verlet_nper", "2e4", "r", done))
        @test Cases.estimate_problem(c, "verlet_nper", "1e4", "order 2 from one run", none) === nothing

        # orders of magnitude, both directions, at the band edges
        @test startswith(Cases.magnitude_feedback(1e4, 1.9e4), "within a factor of 2")
        @test startswith(Cases.magnitude_feedback(1e4, 5.1e3), "within a factor of 2")
        @test startswith(Cases.magnitude_feedback(1e4, 9.9e4), "within a factor of 10")
        @test startswith(Cases.magnitude_feedback(1e4, 1.1e3), "within a factor of 10")
        @test occursin("off by 2.0 orders of magnitude; the measured value is larger", Cases.magnitude_feedback(1e2, 1e4))
        @test occursin("smaller", Cases.magnitude_feedback(1e6, 1e3))
        @test occursin("sign differs", Cases.magnitude_feedback(-5, 5))
        @test occursin("not a number", Cases.magnitude_feedback(1, nothing))
        @test occursin("is 0", Cases.magnitude_feedback(1, 0))

        est = [("verlet_nper", "20000", "nper_verlet", 12800)]
        blind = Cases.estimate_lines(est, [CE("verlet_nper", "2e4", 2e4, "one run, order 2", 0)])
        @test any(l -> occursin("committed: 2e4, before your first study check: a blind estimate", l), blind)
        @test any(l -> occursin("how you got it: one run, order 2", l), blind)
        @test !any(l -> occursin("not the committed", l), blind)        # 20000 == 2e4 as numbers
        @test any(l -> occursin("committed estimate: within a factor of 2", l), blind)
        late = Cases.estimate_lines(est, [CE("verlet_nper", "1.3e4", 1.3e4, "read it off a check", 2)])
        @test any(l -> occursin("after 2 study check(s)", l) && occursin("not a blind estimate", l), late)
        @test any(l -> occursin("not the committed 1.3e4", l), late)   # the report changed the estimate
        nc = Cases.estimate_lines(est, CE[])
        @test any(l -> occursin("not committed", l), nc)
        @test any(l -> occursin("report estimate: within a factor of 2", l), nc)

        # the record: commit, refuse a second commit, count study checks, keep the order
        mktempdir() do dir
            ok, msg = Cases.commit_estimate(c, dir, "verlet_nper", "1e4", "  order 2, one run at h = 0.01  ")
            @test ok && occursin("before any study check", msg)
            ok2, msg2 = Cases.commit_estimate(c, dir, "verlet_nper", "2e4", "changed my mind")
            @test !ok2 && occursin("already committed", msg2)
            es, n = Cases.load_estimates(dir)
            @test n == 0 && only(es).reason == "order 2, one run at h = 0.01" && only(es).study_checks_before == 0
            Cases.save_estimates(dir, es, 3)
            rm(joinpath(dir, Cases.ESTIMATES_FILE))
            Cases.save_estimates(dir, CE[], 3)                          # three checks ran, then a late commit
            ok3, msg3 = Cases.commit_estimate(c, dir, "verlet_nper", "12800", "copied from the check")
            @test ok3 && occursin("not a blind estimate", msg3)
            @test only(first(Cases.load_estimates(dir))).study_checks_before == 3
        end

        # assess: without a record the old text is unchanged; with one, the new block
        text = replace(read(Cases.reference_report(c), String), "\r\n" => "\n")
        vals = written_values(c, text)
        raw = Dict{String,Any}("complete" => true, "runs" => Any[])    # acceptance results are not under test here
        _, plain = Cases.assess(c, 3, raw, vals, vals, text)
        @test occursin("verlet_nper: you estimated 10000; you measured nper_verlet = ", plain)
        _, rec = Cases.assess(c, 3, raw, vals, vals, text; committed = [CE("verlet_nper", "1e4", 1e4, "r", 0)])
        @test occursin("committed: 1e4, before your first study check", rec)
        @test !occursin("you estimated", rec)
    end
end
