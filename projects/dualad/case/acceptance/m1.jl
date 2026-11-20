# Hidden acceptance tests, milestone 1 (stage-1 holes: mul, div, chain,
# power, derivative). Other functions and points than the visible tests in
# the starter, so code fitted to those does not pass by accident. Every
# tolerance is derived in a comment; nothing is random.

using Test
using DualAD

const EPS = eps(Float64)

# Dual equality for tests: both parts, exactly. (`isequal` and `==` on duals
# compare the values only, by design, so they cannot test a derivative.)
same(a, b) = value(a) == value(b) && partial(a) == partial(b)

@testset "product-rule-both-terms" begin
    # (u v)' = u'v + uv', exact on small dyadic numbers. Each case makes one
    # of the two terms 0 in turn, then both nonzero.
    @test same(Dual(5.0, 0.0) * Dual(3.0, 2.0), Dual(15.0, 10.0))
    @test same(Dual(5.0, 2.0) * Dual(3.0, 0.0), Dual(15.0, 6.0))
    @test same(Dual(0.5, 4.0) * Dual(-2.0, 8.0), Dual(-1.0, -4.0))    # 4*(-2) + 0.5*8
    # x^2 (1 - x) written as products: d/dx = 2x - 3x^2, exact at x = 0.25.
    @test isequal(derivative(x -> x * x * (1 - x), 0.25), 0.3125)
end

@testset "quotient-rule-sign-and-square" begin
    # (u/v)' = (u'v - uv') / v^2, exact on dyadic numbers. v = 4 separates
    # v^2 from v; u'v = uv' would hide a sign error, so these avoid it.
    @test same(Dual(2.0, 1.0) / Dual(4.0, 1.0), Dual(0.5, 0.125))      # (4 - 2) / 16
    @test same(Dual(2.0, 0.0) / Dual(4.0, 2.0), Dual(0.5, -0.25))      # -4 / 16
    @test isequal(derivative(x -> x / (1 + x), 1.0), 0.25)               # 1 / (1 + x)^2
    # A zero divisor gives what Float64 gives, not an error.
    @test isinf(value(Dual(1.0, 0.0) / Dual(0.0, 1.0)))
end

@testset "chain-rule-through-compositions" begin
    # Compositions of elementary functions. Each derivative is a handful of
    # correctly rounded operations: bound 16 eps relative (up to 8 roundings,
    # each <= eps/2, and products of them, with a factor 2 margin).
    for x in (0.4, 1.1)
        @test isapprox(derivative(t -> exp(sin(t)), x), cos(x) * exp(sin(x)); rtol = 16EPS)
        @test isapprox(derivative(t -> log(1 + t * t), x), 2x / (1 + x^2); rtol = 16EPS)
        @test isapprox(derivative(t -> sqrt(cos(t)), x), -sin(x) / (2sqrt(cos(x))); rtol = 16EPS)
        @test isapprox(derivative(t -> sin(3t + 1), x), 3cos(3x + 1); rtol = 16EPS)
    end
    # lift with a derivative part other than 1 or 0: f = exp, at Dual(0, 5).
    @test same(lift(exp, exp, Dual(0.0, 5.0)), Dual(1.0, 5.0))
end

@testset "power-rule-edge-exponents" begin
    # n = 0 at 0 is the constant 1 (not NaN); negative and large n; exact on
    # dyadic values. Variable exponents: a literal negative power lowers to
    # inv(x)^n (Base.literal_pow) and would test division instead.
    z, four, m1, two = 0, 4, -1, 2
    @test same(Dual(0.0, 3.0)^z, Dual(1.0, 0.0))
    @test same(Dual(-3.0, 1.0)^z, Dual(1.0, 0.0))
    @test same(Dual(0.5, 2.0)^four, Dual(0.0625, 1.0))                # 4 * 0.125 * 2
    @test same(Dual(4.0, 1.0)^m1, Dual(0.25, -0.0625))
    @test same(Dual(0.0, 1.0)^two, Dual(0.0, 0.0))
    @test isequal(derivative(x -> x^7, 1.0), 7.0)
end

@testset "derivative-one-seeded-pass" begin
    # Exact on a polynomial with small integer coefficients at dyadic
    # points; one evaluation; Int and Float32-free conversion of x.
    q(x) = x^4 - 4x^3 + 2x
    dq(x) = 4x^3 - 12x^2 + 2
    for x in (-0.5, 0.125, 3.0)
        @test isequal(derivative(q, x), dq(x))
    end
    @test isequal(derivative(q, 3), dq(3.0))
    @test isequal(derivative(x -> 2.5, 4.0), 0.0)
    n = Ref(0)
    @test isequal(derivative(x -> (n[] += 1; 3x), 1.0), 3.0)
    @test n[] == 1
    # Second derivative by nesting: (x^3)'' = 6x, exact at x = 2.
    @test isequal(derivative(x -> derivative(t -> t^3, x), 2.0), 12.0)
end
