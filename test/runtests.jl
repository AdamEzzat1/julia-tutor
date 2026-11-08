# Tests for the tutor itself. `TUTOR_FAST=1` skips the subprocess-heavy parts
# (runner, explain, lesson-key verification). CI runs everything.

using Test, TOML, Dates
using JuliaSyntax
using JuliaTutor
using JuliaTutor: Syntax, Checker, Models, Scaffold, Runner, Explain, Lessons, HoleMap, Progress, Fixtures

const ROOT = JuliaTutor.ROOT
const FAST = get(ENV, "TUTOR_FAST", "0") == "1"
const SYMDIFF = Scaffold.load_project(joinpath(ROOT, "projects", "symdiff"))

include("checker_cases.jl")

findings_for(src; file = "t.jl") = Checker.check_source(src, file)
rule_hits(src, id) = filter(f -> f.rule == id, findings_for(src))

@testset "JuliaTutor" begin

@testset "pinned toolchain" begin
    @test VERSION == JuliaTutor.PINNED_JULIA
    @test pkgversion(JuliaSyntax) == v"1.0.2"
    @test Threads.nthreads() == 1
    manifest = TOML.parsefile(joinpath(ROOT, "Manifest.toml"))
    @test manifest["julia_version"] == string(VERSION)
    sym = TOML.parsefile(joinpath(ROOT, "projects", "symdiff", "reference", "Manifest.toml"))
    @test sym["julia_version"] == string(VERSION)
end

@testset "syntax tree shapes the rules rely on" begin
    t = JuliaSyntax.parseall(SyntaxNode, "a == b\nv .= w\nf(x) = x\nv[i] -= 1\n")
    s = Syntax.kids(t)
    @test kind(s[1]) == K"call" && Syntax.is_infix(s[1]) && Syntax.ident(Syntax.kids(s[1])[2]) === :(==)
    @test kind(s[2]) == K"=" && Syntax.is_dotop(s[2])
    @test Syntax.is_short_function(s[3])
    @test kind(s[4]) == K"op=" && kind(Syntax.kids(s[4])[1]) == K"ref"
end

@testset "parser agreement: JuliaSyntax package vs Base parser" begin
    # The checker uses JuliaSyntax.jl 1.0.2; Base 1.10 bundles its own copy. On
    # our corpus both must produce the same Expr, or rule positions could lie.
    files = [joinpath(ROOT, "projects", "symdiff", "reference", "src", "SymDiff.jl"),
             joinpath(ROOT, "projects", "symdiff", "reference", "test", "runtests.jl"),
             joinpath(ROOT, "src", "checker.jl"), joinpath(ROOT, "src", "syntax.jl")]
    for f in files
        src = read(f, String)
        @test JuliaSyntax.parseall(Expr, src; filename = f) == Meta.parseall(src; filename = f)
    end
end

@testset "rule metadata" begin
    ids = [Checker.meta(r).id for r in Checker.RULES]
    @test allunique(ids)
    @test length(ids) >= 5
    for r in Checker.RULES
        m = Checker.meta(r)
        @test all(!isempty, m.hints)
        @test !isempty(m.fp_risk) && !isempty(m.kc) && !isempty(m.answer_tokens)
        # Level-1 hints never give the answer.
        for tok in m.answer_tokens
            @test !occursin(tok, m.hints[1])
        end
        @test haskey(CASES, m.id)
    end
end

@testset "rule $id" for id in sort!(collect(keys(CASES)))
    c = CASES[id]
    @test length(c.positive) >= 1 && length(c.negative) >= 2 && length(c.styles) >= 1
    for src in c.positive
        @test !isempty(rule_hits(src, id))
    end
    for src in c.negative
        @test isempty(rule_hits(src, id))
    end
    # Style tolerance: two different correct styles, zero findings from *any* rule.
    for (a, b) in c.styles
        @test a != b
        @test isempty(findings_for(a))
        @test isempty(findings_for(b))
    end
end

@testset "severity and exit code" begin
    in_test = only(rule_hits("@test x == 0.5", "JT006"))
    outside = only(rule_hits("if x == 0.5\nend", "JT006"))
    @test in_test.severity == Checker.WARN
    @test outside.severity == Checker.ADVICE
    # ADVICE never changes the exit code (invariant 2).
    @test Checker.exit_code([outside]) == 0
    @test Checker.exit_code(rule_hits("function total!(v)\n    return sum(v)\nend", "JT004")) == 0
    @test Checker.exit_code([in_test]) == 1
    perr = findings_for("function f(\n")
    @test only(perr).rule == "JT000" && only(perr).severity == Checker.ERROR
end

@testset "determinism (invariant 3)" begin
    dir = mktempdir()
    srcs = vcat((CASES[id].positive for id in sort!(collect(keys(CASES))))...)
    # write files in reverse order: output must not depend on creation order
    for (i, s) in Iterators.reverse(collect(enumerate(srcs)))
        write(joinpath(dir, "case$(lpad(i, 2, '0')).jl"), s)
    end
    a = Checker.format_findings(Checker.check_paths([dir]; relative_to = dir); hints = 3)
    b = Checker.format_findings(Checker.check_paths([dir]; relative_to = dir); hints = 3)
    @test a == b
    @test !isempty(a)
    fs = Checker.check_paths([dir]; relative_to = dir)
    @test issorted(fs; by = Checker.sortkey)
end

@testset "reference solutions are clean" begin
    ref = Scaffold.reference_dir(SYMDIFF)
    fs = Checker.check_paths([joinpath(ref, "src"), joinpath(ref, "test")]; relative_to = ref)
    @test filter(f -> f.severity >= Checker.WARN, fs) == Checker.Finding[]
end

@testset "models" begin
    θ = Models.BKTParams()
    # Hand-computed (see models.jl formulas); <= 10 flops each, well conditioned,
    # so rounding error ~1e-15 relative; 1e-12 is a safe bound.
    @test isapprox(Models.bkt_update(0.2, true, θ), 0.18 / 0.38 + (1 - 0.18 / 0.38) * 0.15; rtol = 1e-12)
    @test isapprox(Models.bkt_update(0.2, true, θ), 0.5526315789473684; rtol = 1e-12)
    @test isapprox(Models.bkt_update(0.2, false, θ), 0.02 / 0.62 + (1 - 0.02 / 0.62) * 0.15; rtol = 1e-12)
    @test Models.bkt_update(0.5, true, θ) > 0.5 > Models.bkt_update(0.5, false, θ)
    @test_throws ArgumentError Models.BKTParams(0.2, 0.1, 0.6, 0.5)
    s1 = Models.sm2_update(Models.SM2State(), 5)
    s2 = Models.sm2_update(s1, 5)
    s3 = Models.sm2_update(s2, 5)
    @test (s1.repetitions, s1.interval_days, s2.interval_days, s3.interval_days) == (1, 1, 6, 16)
    @test isapprox(s3.easiness, 2.8; rtol = 1e-12)
    lapse = Models.sm2_update(s3, 1)
    @test (lapse.repetitions, lapse.interval_days) == (0, 1)
    @test isapprox(Models.sm2_update(Models.SM2State(), 2).easiness, 2.18; rtol = 1e-12)
    @test Models.sm2_update(Models.SM2State(0, 0, 1.3), 0).easiness >= 1.3
    @test Models.sm2_due(s2, Date(2026, 11, 8)) == Date(2026, 11, 14)
    @test Models.ochiai(2, 0, 2) == 1.0                  # exact: 2 / sqrt(4)
    @test isapprox(Models.ochiai(1, 1, 2), 0.5; rtol = 1e-15)
    @test Models.ochiai(0, 3, 1) == 0.0
    @test Models.ochiai(0, 0, 0) == 0.0
    deps = Dict("a" => ["t1", "t2"], "b" => ["t1"], "c" => ["t3"])
    r = Models.rank_by_ochiai(deps, Set(["t1"]), ["a", "b", "c"])
    @test [x[1] for x in r] == ["b", "a", "c"]
    tie = Models.rank_by_ochiai(Dict("a" => ["t1"], "b" => ["t1"]), Set(["t1"]), ["b", "a"])
    @test [x[1] for x in tie] == ["b", "a"]               # ties keep teaching order
end

@testset "scaffolder" begin
    src = """
    module M
    # HOLE: one
    \"\"\"Doc for f.\"\"\"
    function f(x)
        y = "end"   # a string containing end
        if x > 0
            return y
        end
        return x
    end
    # HOLE: two
    function g(x)::Int where {T}
        return 2
    end
    end
    """
    out = Scaffold.render_source(src, "m.jl", Dict("one" => Scaffold.todo_body("one")))
    @test !occursin("# HOLE", out)
    @test occursin("\"\"\"Doc for f.\"\"\"\nfunction f(x)\n    error(\"TODO(hole:one)\")\nend", out)
    @test !occursin("a string containing end", out)          # no answer leakage
    @test occursin("return 2", out)                          # unopened hole keeps its body
    @test Scaffold.hole_body_is_todo(out, "m.jl", "one")
    @test_throws ErrorException Scaffold.find_holes("# HOLE: x\nconst y = 1\n", "bad.jl")
    @test_throws ErrorException Scaffold.find_holes("# HOLE: x\nf(x) = 1\n", "short.jl")
    # Invariant 6: the committed starter is exactly what the scaffolder generates.
    @test Scaffold.check_starter(SYMDIFF) == String[]
    # Invariant 5: every opened hole is exactly the TODO body (plus its docstring).
    for stage in SYMDIFF.stages
        files = Scaffold.starter_files(SYMDIFF, stage)
        for h in SYMDIFF.holes
            src = files[h.file]
            @test Scaffold.hole_body_is_todo(src, h.file, h.id) == (h.stage <= stage)
        end
    end
    # Fading: later stages open strictly more holes.
    counts = [count(h -> h.stage <= s, SYMDIFF.holes) for s in SYMDIFF.stages]
    @test issorted(counts) && allunique(counts)
end

@testset "lessons: structure" begin
    lessons = Lessons.load_lessons()
    @test length(lessons) >= 2
    @test Lessons.validate_lessons(lessons) == String[]
end

@testset "lessons: hint before reveal, BKT and SM-2 state" begin
    l = Lessons.load_lessons()[1]
    state = joinpath(mktempdir(), "state.toml")
    # check 1: wrong (b) then right (a); check 2: right (c); check 3: wrong twice (b, c)
    out = IOBuffer()
    results, st = Lessons.run_lesson(l; input = IOBuffer("b\na\nc\nb\nc\n"), output = out,
                                     state_path = state, today = Date(2026, 11, 8))
    text = String(take!(out))
    @test results == [false, true, false]
    first_wrong = findfirst("Not quite.", text)
    @test findfirst("Hint:", text).start > first_wrong.start
    @test !occursin("The answer is a)", text[1:findfirst("Correct on the second try.", text).start])
    @test occursin("The answer is a)", text)
    saved = TOML.parsefile(state)
    @test saved["misconceptions"]["first-match-wins"] == 1
    @test saved["items"]["L01-dispatch/specificity"]["repetitions"] == 1   # quality 3
    @test saved["items"]["L01-dispatch/runtime-types"]["repetitions"] == 0 # quality 1
    @test saved["items"]["L01-dispatch/runtime-types"]["due"] == "2026-11-09"
    @test 0 < saved["kc"]["multiple-dispatch"] < 1
end

@testset "learner model: evidence from hole attempts" begin
    deps = Dict("a" => ["T1", "T2"], "b" => ["T2", "T3"], "c" => String[])
    stage = ["a", "b", "c"]
    @test Progress.observe("a", deps, Set{String}(), stage) == :correct
    @test Progress.observe("a", deps, Set(["T1"]), stage) == :incorrect     # T1 depends on a only
    @test Progress.observe("a", deps, Set(["T2"]), stage) == :ambiguous     # T2 is shared with b
    @test Progress.observe("b", deps, Set(["T2", "T3"]), stage) == :incorrect
    @test Progress.observe("c", deps, Set(["T1"]), stage) == :no_evidence   # no dependent testset
    # A hole of a later stage is not a competing explanation at this stage.
    @test Progress.observe("a", deps, Set(["T2"]), ["a"]) == :incorrect
    # T2 fails only through b's TODO error: excused, so a's fix is credited ...
    @test Progress.observe("a", deps, Set(["T2"]), stage; excused = Set(["T2"])) == :correct
    # ... but an excused testset is never the only evidence.
    @test Progress.observe("b", Dict("b" => ["T2"]), Set(["T2"]), ["b"]; excused = Set(["T2"])) == :no_evidence

    @test Progress.attempt_hash("x = 1\n  y") == Progress.attempt_hash("x=1 y")   # whitespace-insensitive
    @test Progress.attempt_hash("x = 1") != Progress.attempt_hash("x = 2")

    # BKT with CODE_BKT (p_guess 0.05, p_slip 0.15, p_learn 0.15) from the 0.2 prior,
    # hand-computed: incorrect -> 0.0379747 + 0.9620253 * 0.15 = 0.1822785;
    # correct -> 0.8095238 + 0.1904762 * 0.15 = 0.8380952.
    state = Dict{String,Any}()
    o1 = Progress.Observation("symdiff", "product_rule", "kc1", false, "h1")
    lines = Progress.apply_observations!(state, [o1])
    @test isapprox(state["kc"]["kc1"], 0.1822785; atol = 1e-6)
    @test occursin("attempt 1, incorrect", only(lines))
    # The same code again is not new evidence (no mastery inflation by re-running).
    lines = Progress.apply_observations!(state, [o1])
    @test occursin("not counted again", only(lines))
    @test isapprox(state["kc"]["kc1"], 0.1822785; atol = 1e-6)
    @test state["holes"]["symdiff/product_rule"]["attempts"] == 1
    st2 = Dict{String,Any}()
    Progress.apply_observations!(st2, [Progress.Observation("symdiff", "product_rule", "kc1", true, "h2")])
    @test isapprox(st2["kc"]["kc1"], 0.8380952; atol = 1e-6)

    # The progress report is deterministic given state and date.
    state["items"] = Dict{String,Any}("L01-dispatch/specificity" => Dict("due" => "2026-11-08"),
                                      "L01-dispatch/ambiguity" => Dict("due" => "2026-11-20"))
    rep = Progress.format_progress(state; today = Date(2026, 11, 8))
    @test rep == Progress.format_progress(deepcopy(state); today = Date(2026, 11, 8))
    @test occursin("symdiff/product_rule", rep) && occursin("attempts 1, correct 0, last incorrect", rep)
    @test occursin("L01-dispatch/specificity (due 2026-11-08)", rep)
    @test !occursin("L01-dispatch/ambiguity (due", rep)
end

@testset "explain fixtures: structure" begin
    fx = Fixtures.load_fixtures(SYMDIFF)
    @test Fixtures.validate_fixtures(SYMDIFF, fx) == String[]
    @test Set(f.hole for f in fx) ⊇ Set(h.id for h in SYMDIFF.holes)          # every hole has one
    @test all(f -> isfile(Fixtures.golden_path(SYMDIFF, f)), fx)
    # Each fixture's body really differs from the reference body (it is a bug).
    # (Compared with the reference materialised the same way: markers stripped.)
    refdir = HoleMap.materialize(SYMDIFF, Dict{String,String}())
    ref = read(joinpath(refdir, "src", "SymDiff.jl"), String)
    rm(refdir; recursive = true)
    @test all(fx) do f
        dir = Fixtures.materialize(SYMDIFF, f)
        changed = read(joinpath(dir, "src", "SymDiff.jl"), String) != ref
        rm(dir; recursive = true)
        changed
    end
end

if !FAST
    @testset "lessons: answer keys verified on the pinned Julia" begin
        @test Lessons.verify_lessons(Lessons.load_lessons(); log = devnull) == String[]
    end

    @testset "runner + explain on the stage-1 starter" begin
        dir = joinpath(mktempdir(), "work")
        files = Scaffold.starter_files(SYMDIFF, 1)
        for (rel, s) in files
            mkpath(dirname(joinpath(dir, rel)))
            write(joinpath(dir, rel), s)
        end
        rep = Runner.run_tests(dir)
        @test isempty(rep.crash)
        bad = filter(!Runner.ok, rep.testsets)
        @test !isempty(bad)
        seen = Set(h for t in rep.testsets for h in t.holes)
        @test seen == Set(["product_rule", "pvar_binding", "size_measure"])

        # A student fills product_rule with an aliasing bug and pvar_binding with a
        # body that mutates its argument: explain must point at the right hole
        # and attach the static finding.
        path = joinpath(dir, "src", "SymDiff.jl")
        src = read(path, String)
        src = replace(src, "    error(\"TODO(hole:product_rule)\")" =>
            "    summands = Term[]\n    for i in eachindex(t.args)\n        factors = t.args\n" *
            "        factors[i] = deriv(t.args[i], x)\n        push!(summands, Mul(copy(factors)))\n" *
            "    end\n    return Add(summands)")
        src = replace(src, "    error(\"TODO(hole:pvar_binding)\")" =>
            "    if haskey(b, p.name)\n        return b[p.name] == t ? b : nothing\n    end\n" *
            "    b[p.name] = t\n    return b")
        write(path, src)
        r = Explain.explain(SYMDIFF, dir; hints = 1)
        txt = r.text
        @test r.exitcode == 1
        @test occursin("Start here: hole `", txt)
        @test occursin("JT003 `match_pattern` mutates its argument `b`", txt)
        @test occursin("size_measure", txt) && occursin("not started", txt)
        @test occursin("Measurements (fresh process", txt)
        # The aliasing bug in product_rule must not leak into other measurements:
        # each measurement gets a fresh bench, so evaluate (no hole) is unchanged.
        @test occursin(r"allocations evaluate\(bench, Float64\): \d+  \(reference \d+\)", txt)
        # Printed test expressions carry no `#= file:line =#` line-number comments.
        @test !occursin("#=", txt)
        # explain output contains no absolute paths of the student's machine
        @test !occursin(replace(dir, '\\' => '/'), replace(txt, '\\' => '/'))
    end
end

end # JuliaTutor
