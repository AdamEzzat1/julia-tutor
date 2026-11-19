# Behavioural specification of DualAD.
#
# Evidence of three kinds, each tolerance derived in a comment (invariant 9):
# * exact cases: on a polynomial with small integer coefficients at a
#   dyadic point every Float64 operation is exact, so a dual derivative must
#   equal the exact derivative (both parts compared exactly by `same`);
# * rounding-level cases: an elementary function's derivative is within a
#   few eps of the exact value (each bound counts the operations);
# * the central difference's error model: order 2 where truncation
#   dominates (a least-squares fit, window +- 0.1), and the 1/h growth of
#   rounding error at small h.
# Nothing is random.

using Test
using DualAD

const EPS = eps(Float64)

# Dual equality for tests: both parts, exactly. (`isequal` and `==` on duals
# compare the values only, by design, so they cannot test a derivative.)
same(a, b) = value(a) == value(b) && partial(a) == partial(b)

@testset "Dual: construction, promotion, comparison" begin
    @test Dual(1, 2.0) isa Dual{Float64}
    @test same(value(Dual(3.0, 4.0)), 3.0) && same(partial(Dual(3.0, 4.0)), 4.0)
    @test isequal(partial(5.0), 0.0) && isequal(value(5.0), 5.0)
    @test promote_type(Dual{Float64}, Int) == Dual{Float64}
    @test convert(Dual{Float64}, 2) === Dual(2.0, 0.0)
    @test Dual(1.0, 5.0) == Dual(1.0, -3.0)            # comparisons look at the value only
    @test Dual(1.0, 5.0) < Dual(2.0, 0.0) && Dual(2.0, 1.0) <= 2
    @test hash(Dual(1.0, 5.0)) == hash(Dual(1.0, 0.0))
    @test sprint(show, Dual(1.5, -2.0)) == "Dual(1.5, -2.0)"
    @test same(Dual(1.0, 2.0) + 3, Dual(4.0, 2.0))
    @test same(-Dual(1.0, 2.0), Dual(-1.0, -2.0))
    @test same(abs(Dual(-2.0, 3.0)), Dual(2.0, -3.0))
end

@testset "mul: the product rule" begin
    # Exact: small integers.
    @test same(Dual(3.0, 1.0) * Dual(4.0, 2.0), Dual(12.0, 10.0))   # 1*4 + 3*2
    @test same(Dual(3.0, 1.0) * Dual(4.0, 0.0), Dual(12.0, 4.0))
    @test same(2 * Dual(3.0, 1.0), Dual(6.0, 2.0))                   # promotion: 2 is Dual(2, 0)
    @test isequal(derivative(x -> x * x * x, 2.0), 12.0)
end

@testset "div: the quotient rule" begin
    # Exact: dyadic values. (u/v)' = (u'v - uv') / v^2.
    @test same(Dual(1.0, 0.0) / Dual(2.0, 1.0), Dual(0.5, -0.25))
    @test same(Dual(3.0, 1.0) / Dual(2.0, 0.0), Dual(1.5, 0.5))
    @test same(Dual(4.0, 2.0) / Dual(2.0, 1.0), Dual(2.0, 0.0))     # u = 2v: the quotient is constant
    @test isequal(derivative(x -> 1 / x, 4.0), -0.0625)
end

@testset "chain: elementary functions" begin
    # Each derivative is a few roundings of a correctly rounded function:
    # bound 4 eps relative.
    for x in (0.3, 1.7, -2.5)
        @test isapprox(derivative(sin, x), cos(x); rtol = 4EPS)
        @test isapprox(derivative(cos, x), -sin(x); rtol = 4EPS)
        @test isapprox(derivative(exp, x), exp(x); rtol = 4EPS)
        @test isapprox(derivative(t -> sin(2t), x), 2cos(2x); rtol = 4EPS)   # the inner derivative 2
    end
    @test isapprox(derivative(log, 3.0), 1 / 3; rtol = 4EPS)
    @test isapprox(derivative(sqrt, 9.0), 1 / 6; rtol = 4EPS)
    @test same(lift(sin, cos, Dual(0.0, 3.0)), Dual(0.0, 3.0))           # cos(0) * 3
end

@testset "power: integer exponents" begin
    # The exponents are variables on purpose: a literal negative power such
    # as x^-2 lowers to Base.literal_pow, which computes inv(x)^2 for any
    # type that is not a hardware number, so it tests the quotient rule, not ^.
    three, minus2, zero_, one_ = 3, -2, 0, 1
    @test same(Dual(2.0, 1.0)^three, Dual(8.0, 12.0))
    @test same(Dual(2.0, 0.5)^three, Dual(8.0, 6.0))                     # 3 * 4 * 0.5
    @test same(Dual(2.0, 1.0)^minus2, Dual(0.25, -0.25))                 # -2 * 2^-3
    @test same(Dual(0.0, 1.0)^zero_, Dual(1.0, 0.0))                     # not 0 * 0^-1 = NaN
    @test same(Dual(5.0, 1.0)^one_, Dual(5.0, 1.0))
    @test isequal(derivative(x -> x^2, 3.0), 6.0)                        # a positive literal reaches ^ unchanged
end

@testset "derivative: one evaluation on a seeded dual" begin
    p(x) = 3x^5 - 2x^3 + x^2 - 7x + 4
    dp(x) = 15x^4 - 6x^2 + 2x - 7
    for x in (0.75, -1.5, 2.0)
        @test isequal(derivative(p, x), dp(x))                             # exact: see the header
    end
    @test isequal(derivative(p, 2), dp(2.0))                                # an Int point is converted
    @test isequal(derivative(x -> 7.0, 1.0), 0.0)                           # a constant function
    @test isequal(derivative(abs, -2.0), -1.0)
    # Nested duals: the second derivative of sin is -sin (4 eps, as above).
    @test isapprox(derivative(x -> derivative(sin, x), 0.5), -sin(0.5); rtol = 4EPS)
    calls = Ref(0)
    derivative(x -> (calls[] += 1; x * x), 1.0)
    @test calls[] == 1
end

@testset "gradient: one evaluation per component" begin
    g(x) = x[1] * x[2] + 3 * x[3]^2 - x[1]
    @test isequal(gradient(g, [2.0, 5.0, 1.0]), [4.0, 2.0, 6.0])           # exact: integers
    @test isequal(gradient(g, [2, 5, 1]), [4.0, 2.0, 6.0])                  # Int input
    calls = Ref(0)
    gradient(x -> (calls[] += 1; sum(x)), zeros(4))
    @test calls[] == 4
    h(x) = sin(x[1]) * exp(x[2])
    gh = gradient(h, [0.3, 0.2])
    @test isapprox(gh[1], cos(0.3) * exp(0.2); rtol = 8EPS)
    @test isapprox(gh[2], sin(0.3) * exp(0.2); rtol = 8EPS)
end

@testset "central_diff: exact on quadratics, order 2" begin
    # On a quadratic the central difference has no truncation error: with
    # dyadic x and h every operation is exact.
    @test isequal(central_diff(x -> x^2 + 3x, 1.0, 0.25), 5.0)
    @test isequal(central_diff(x -> 2x, 10.0, 0.5), 2.0)
    # Order 2 on sin at x = 1 over h = 2^-3 .. 2^-8 (truncation dominates:
    # the error is >= 1e-6 there, rounding <= 1e-14): fit window 2 +- 0.1.
    hs = [2.0^-k for k in 3:8]
    errs = [abs(central_diff(sin, 1.0, h) - cos(1.0)) for h in hs]
    @test 1.9 <= fit_order(hs, errs) <= 2.1
    # Halving h divides the error by 4 (+ O(h^2): within 1%).
    @test isapprox(errs[1] / errs[2], 4; rtol = 0.01)
end

@testset "fit_order: least squares on log-log" begin
    @test isapprox(fit_order([0.1, 0.01, 0.001], [3e-2, 3e-4, 3e-6]), 2; rtol = 1e-12)
    # Not the end-point slope: the middle point moves the least-squares fit.
    hs = [1.0, 0.25, 0.125]
    errs = [1.0, 0.5, 1 / 64]
    x, y = log.(hs), log.(errs)
    xm, ym = sum(x) / 3, sum(y) / 3
    ls = sum((x .- xm) .* (y .- ym)) / sum(abs2, x .- xm)
    @test isapprox(fit_order(hs, errs), ls; rtol = 1e-12)
    @test !isapprox(fit_order(hs, errs), (y[3] - y[1]) / (x[3] - x[1]); rtol = 0.01)
    @test_throws ArgumentError fit_order([1.0], [1.0])
    @test_throws ArgumentError fit_order([1.0, 0.5], [1.0, 0.0])
end

@testset "dual numbers vs central differences at the same point" begin
    # The dual derivative of exp(x) sin(x) is at rounding level (8 eps:
    # three functions and four operations); the best central difference on
    # a 2^-k grid is near 1e-11 to 1e-12, never at rounding level.
    f(x) = exp(x) * sin(x)
    df(x) = exp(x) * (sin(x) + cos(x))
    @test isapprox(derivative(f, 0.7), df(0.7); rtol = 8EPS)
    best = minimum(abs(central_diff(f, 0.7, 2.0^-k) / df(0.7) - 1) for k in 1:52)
    @test best > 1e-14
end

@testset "babylonian_sqrt: the derivative of an algorithm" begin
    # After 6 Newton steps from 1 the iteration has converged for a = 2
    # (error 1.6e-16 after 5); the derivative of the code is then the
    # derivative of sqrt to rounding (8 eps).
    d = babylonian_sqrt(Dual(2.0, 1.0); iters = 6)
    @test isapprox(value(d), sqrt(2.0); rtol = 4EPS)
    @test isapprox(partial(d), 1 / (2sqrt(2.0)); rtol = 8EPS)
    # After 2 steps it has not, and neither has the derivative.
    d2 = babylonian_sqrt(Dual(2.0, 1.0); iters = 2)
    @test abs(partial(d2) * 2sqrt(2.0) - 1) > 1e-3
end
