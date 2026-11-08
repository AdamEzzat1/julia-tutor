# Behavioural specification of SymDiff.
#
# Tests check outcomes, not code shape: derivatives are checked by evaluating
# them (exactly, with rationals, where possible) and comparing with known
# derivatives; canonical-form tests check the normal form that `simplify`'s
# docstring specifies. Float comparisons always state their tolerance and why.
# No randomness: the "property" tests enumerate small terms exhaustively.

using Test
using SymDiff

const x = Sym(:x)
const y = Sym(:y)
const z = Sym(:z)
const w = Sym(:w)

const ExactEnv = Dict{Symbol,Rational{BigInt}}
exact(t::Term, xv, yv = 0) = evaluate(t, ExactEnv(:x => xv, :y => yv))
num(t::Term, xv::Float64) = evaluate(t, Dict(:x => xv))

# Elementary-function tolerance. Each side below is evaluated with at most ~30
# Float64 operations, each with relative error <= 1 ulp (Julia's libm sin, cos,
# exp, log are faithfully rounded, < 1 ulp). The sample points keep |f'| >= 0.2
# and every case's relative condition number <= ~30 (checked by hand: the worst
# is 1 + log(v) at v = 0.3, cond ~ 11). Error bound per side ~ 30 * 30 * eps,
# so 1e3 * eps covers the difference of two such evaluations.
const RTOL_ELEMENTARY = 1e3 * eps(Float64)
const POINTS = (0.3, 0.7, 1.1, 1.9)

const ATOMS = Term[Const(0), Const(1), Const(-2), Const(1 // 2), x, y]

"""Every term built from ATOMS with one `+`, `*` or `^2` (deterministic)."""
function level1()
    ts = Term[]
    for a in ATOMS, b in ATOMS
        push!(ts, a + b, a * b)
    end
    for a in ATOMS
        push!(ts, a^2)
    end
    return ts
end

const R_LOGEXP = @rule log(exp(~u)) => ~u
const R_PYTH = @rule cos(~u)^2 + sin(~u)^2 => 1
const R_DIST = @rule ~a * (~b + ~c) => ~a * ~b + ~a * ~c
const R_COMM = @rule ~a + ~b => ~b + ~a

@testset "SymDiff" begin

@testset "construction and equality" begin
    @test Add(Term[x, y]) == Add(Term[x, y])
    @test hash(Add(Term[x, y])) == hash(Add(Term[x, y]))
    @test Add(Term[x, y]) != Mul(Term[x, y])
    @test sin(x) != cos(x)
    @test length(Set([Add(Term[x, y]), Add(Term[x, y]), Mul(Term[x, y])])) == 2
    @test_throws ArgumentError Const(0.5)
end

@testset "parsing and printing" begin
    @test @term(x^2 + 1) == Add(Term[Pow(x, Const(2)), Const(1)])
    @test @term(sin(x)) == Fn(sin, x)
    @test @term(2 // 3) == Const(2 // 3)
    @test @term(~a + 1) == Add(Term[PVar(:a), Const(1)])
    @test_throws ArgumentError term(:(foo(x)))
    @test_throws ArgumentError term(:(x[1]))
    for ex in (:(x^2 + 3x + 1), :(sin(x) * cos(y)), :(exp(x^2) / x), :(log(x) - 2 // 3))
        t = simplify(term(ex))
        @test term(to_expr(t)) == t
    end
    @test sprint(show, simplify(@term x + x)) == "2x"
end

@testset "canonical form: sums" begin
    @test simplify(@term x + x) == @term 2x
    @test simplify(@term 3x + y - 3x) == y
    @test simplify(@term 1 + x + 2) == @term 3 + x
    @test simplify(@term x + 0) == x
    @test simplify(@term x - x) == Const(0)
    @test simplify(@term x + y) == simplify(@term y + x)
    @test simplify(@term (x + y) + 1) == simplify(@term x + (y + 1))
    @test simplify(@term 2x * y + 3y * x) == simplify(@term 5x * y)
end

@testset "canonical form: products and powers" begin
    @test simplify(@term x * x) == @term x^2
    @test simplify(@term x^2 * x^3) == @term x^5
    @test simplify(@term (x^2)^3) == @term x^6
    @test simplify(@term 2 * 3 * x) == @term 6x
    @test simplify(@term 0 * sin(x)) == Const(0)
    @test simplify(@term x^0) == Const(1)
    @test simplify(@term x * x^-1) == Const(1)
    @test simplify(@term (2 // 3)^2) == Const(4 // 9)
    @test simplify(@term x * y) == simplify(@term y * x)
    @test simplify(@term log(exp(x))) == x
    # exp(log(u)) -> u is unsound for u <= 0 and must not be applied.
    @test simplify(@term exp(log(x))) == @term exp(log(x))
    # (x^a)^n -> x^(a n) only for integer n: (x^2)^(1/2) is |x|, not x.
    @test simplify(@term (x^2)^(1 // 2)) == @term (x^2)^(1 // 2)
end

@testset "simplify: idempotent, order-independent, sound (exhaustive)" begin
    # Counterexamples are collected and the first three reported in one test, so a
    # broken simplifier yields a short, readable failure instead of thousands.
    env = ExactEnv(:x => 3 // 7, :y => -5 // 2)
    l1 = level1()
    not_idempotent, unsound, not_commutative, not_associative = Term[], Term[], Term[], Term[]
    for a in l1, b in ATOMS
        for t in (a + b, a * b)
            s = simplify(t)
            simplify(s) == s || push!(not_idempotent, t)
            evaluate(s, env) == evaluate(t, env) || push!(unsound, t)   # exact rationals
        end
        simplify(a + b) == simplify(b + a) || push!(not_commutative, a + b)
        simplify(a * b) == simplify(b * a) || push!(not_commutative, a * b)
    end
    for a in ATOMS, b in ATOMS, c in ATOMS
        simplify((a + b) + c) == simplify(a + (b + c)) || push!(not_associative, (a + b) + c)
        simplify((a * b) * c) == simplify(a * (b * c)) || push!(not_associative, (a * b) * c)
    end
    @test first(not_idempotent, 3) == Term[]
    @test first(unsound, 3) == Term[]
    @test first(not_commutative, 3) == Term[]
    @test first(not_associative, 3) == Term[]
end

@testset "derivative: polynomials (exact)" begin
    p = @term 3x^4 - 2x^3 + x - 7
    dp(v) = 12v^3 - 6v^2 + 1
    for v in (-2 // 1, 0 // 1, 1 // 3, 5 // 2)
        @test exact(derivative(p, :x), v) == dp(v)
    end
    @test derivative(@term(x^3), :x) == @term 3x^2
    @test derivative(@term(y^2), :x) == Const(0)
    @test derivative(@term(7), :x) == Const(0)
end

@testset "derivative: product rule" begin
    @test derivative(@term(x * y), :x) == y
    @test derivative(@term(x * y), :y) == x
    for v in (-2 // 1, 1 // 3, 5 // 2)
        @test exact(derivative(@term(x^2 * (x + 1)), :x), v) == 3v^2 + 2v
        # three factors: d/dx (x+1)(x+2)(x+3) = 3x^2 + 12x + 11
        @test exact(derivative(@term((x + 1) * (x + 2) * (x + 3)), :x), v) == 3v^2 + 12v + 11
        # four factors, two variables: d/dx (x * y * x * (x + y)) = 3x^2 y + 2xy^2
        @test exact(derivative(Mul(Term[x, y, x, x + y]), :x), v, 2) == 3v^2 * 2 + 2v * 4
    end
    # deriv must not mutate its input
    t = Mul(Term[x, Add(Term[x, Const(1)]), Pow(x, Const(3))])
    before = deepcopy(t)
    derivative(t, :x)
    @test t == before
end

@testset "derivative: chain rule and elementary functions" begin
    @test derivative(@term(sin(x)), :x) == @term cos(x)
    @test derivative(@term(exp(2x)), :x) == simplify(@term 2exp(2x))
    @test derivative(@term(log(x)), :x) == @term x^-1
    cases = [
        (@term(sin(x^2)), v -> 2v * cos(v^2)),
        (@term(exp(3x) * cos(x)), v -> exp(3v) * (3cos(v) - sin(v))),
        (@term(log(x^2 + 1)), v -> 2v / (v^2 + 1)),
        (@term(sin(cos(x))), v -> -cos(cos(v)) * sin(v)),
        (@term(x^x), v -> v^v * (log(v) + 1)),
    ]
    for (f, df) in cases, v in POINTS
        @test isapprox(num(derivative(f, :x), v), df(v); rtol = RTOL_ELEMENTARY)
    end
end

@testset "pattern matching" begin
    b = match_pattern(@term(~a + ~b), Add(Term[x, y]))
    @test b !== nothing && b[:a] == x && b[:b] == y
    @test match_pattern(@term(~a + ~a), Add(Term[x, y])) === nothing
    b2 = match_pattern(@term(~a + ~a), Add(Term[x, x]))
    @test b2 !== nothing && b2[:a] == x
    @test match_pattern(@term(sin(~u)), @term cos(x)) === nothing
    @test match_pattern(@term(sin(~u)), @term sin(x^2))[:u] == @term x^2
    @test match_pattern(@term((~u)^2), @term sin(x)^2)[:u] == @term sin(x)
    @test match_pattern(@term(~a * ~b), Add(Term[x, y])) === nothing
    # existing bindings are respected and never mutated
    b0 = Dict{Symbol,Term}(:a => y)
    @test match_pattern(PVar(:a), x, b0) === nothing
    @test match_pattern(PVar(:a), y, b0) == b0
    empty_b = Dict{Symbol,Term}()
    match_pattern(PVar(:a), x, empty_b)
    @test isempty(empty_b)
    @test substitute(@term(~a * ~b + ~a), Dict{Symbol,Term}(:a => x, :b => y)) == @term x * y + x
end

@testset "rewriting" begin
    @test rewrite(@term(log(exp(sin(x)))), [R_LOGEXP]) == @term sin(x)
    @test rewrite(@term(log(exp(log(exp(x))))), [R_LOGEXP]) == x
    @test rewrite(simplify(@term sin(x^2)^2 + cos(x^2)^2), [R_PYTH]) == Const(1)
    @test rewrite(@term(sin(x) + 1), [R_LOGEXP]) == @term sin(x) + 1
    # The result of a rule can contain a new redex; it must be rewritten too.
    @test rewrite(@term(x * (y + (z + w))), [R_DIST]) == @term x * y + (x * z + x * w)
    # Rules are tried in order.
    @test rewrite(@term(log(exp(x))), [@rule(log(exp(~u)) => 0), R_LOGEXP]) == Const(0)
    # Commutativity never terminates; the step budget must stop it.
    @test_throws ErrorException rewrite(@term(x + y), [R_COMM]; maxsteps = 100)
    @test_throws ArgumentError @rule(~a => ~b)    # rhs variable not bound by lhs
end

@testset "termination measure" begin
    @test is_size_decreasing(R_LOGEXP)
    @test is_size_decreasing(R_PYTH)
    @test !is_size_decreasing(R_COMM)                        # equal size
    @test !is_size_decreasing(R_DIST)                        # duplicates ~a
    @test !is_size_decreasing(@rule sin(cos(exp(~a))) => ~a + ~a)   # smaller, but duplicates ~a
    @test !is_size_decreasing(@rule ~a => ~a)
    # Empirical check of the theorem behind the measure on many instances:
    # whenever the rule is size-decreasing, every instance shrinks.
    grew = Rule[]
    for r in (R_LOGEXP, R_PYTH, @rule(~a * 1 => ~a)), u in level1()
        is_size_decreasing(r) || continue
        b = Dict{Symbol,Term}(:u => u, :a => u)
        nodecount(substitute(r.rhs, b)) < nodecount(substitute(r.lhs, b)) || push!(grew, r)
    end
    @test first(grew, 3) == Rule[]
end

@testset "soundness of rewrite rules on known cases" begin
    # log(exp(v)) vs v: exp has relative error <= 1 ulp, log then adds <= 1 ulp
    # plus an absolute error ~eps; for |v| >= 0.3 that is <= ~4 eps relative.
    for v in POINTS
        b = Dict{Symbol,Term}(:u => x)
        @test isapprox(num(substitute(R_LOGEXP.lhs, b), v), num(substitute(R_LOGEXP.rhs, b), v);
                       rtol = 16eps(Float64))
        # cos^2 + sin^2 vs 1: two squares (<= 2 ulp each), one add of positives (<= 1 ulp).
        @test isapprox(num(substitute(R_PYTH.lhs, b), v), 1.0; atol = 8eps(Float64))
    end
    # exp(log(u)) => u would be unsound: the lhs is undefined for u < 0.
    @test_throws DomainError num(@term(exp(log(x))), -1.0)
end

@testset "type stability (measured with @inferred)" begin
    t = simplify(@term 3x^2 + sin(x) * exp(x))
    @test @inferred(evaluate(t, Dict(:x => 0.5))) isa Float64
    @test @inferred(Union{Nothing,Dict{Symbol,Term}},
                    match_pattern(PVar(:a), x, Dict{Symbol,Term}())) isa Dict{Symbol,Term}
    @test @inferred(is_size_decreasing(R_LOGEXP)) isa Bool
end

@testset "no method ambiguities" begin
    @test isempty(Test.detect_ambiguities(SymDiff))
end

end # top-level testset
