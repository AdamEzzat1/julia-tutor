# Acceptance, milestone 4: best_price. One @testset per behaviour id.
#
# Tolerance: LBFGS stops when |g| <= 1e-8 (Optim's default g_abstol). Near
# the optimum p* the price error is about |g| / |f''(p*)|, where f is the
# negated profit. For f(p) = -(p - c) a exp(-b p), f''(p*) = a b exp(-b p*):
# 6.8 for (a, b, c) = (100, 0.5, 2), 2.0 for (50, 0.2, 3) and 99.6 for
# (1000, 2, 1), so the error is below 5e-9 in all three. TOL = 1e-8.
# Observed errors: below 4e-13.
using Production, Test, ForwardDiff

const TOL = 1e-8

@testset "price-optimum" begin
    # d/dp [(p - c) a exp(-b p)] = a exp(-b p) (1 - b (p - c)) = 0  at  p = c + 1 / b.
    for (a, b, c) in ((100.0, 0.5, 2.0), (50.0, 0.2, 3.0), (1000.0, 2.0, 1.0))
        p = best_price(a, b, c)
        @test p isa Float64
        @test isapprox(p, c + 1 / b; atol = TOL)
    end
end

@testset "price-general" begin
    # Linear demand q(p) = 10 - p: (p - c)(10 - p) is a concave quadratic,
    # largest at p = (10 + c) / 2; f'' = 2, so the error bound is 5e-9.
    @test isapprox(best_price(p -> 10 - p, 2.0), 6.0; atol = TOL)
    @test isapprox(best_price(p -> 10 - p, 4.0), 7.0; atol = TOL)
    # The start point is a keyword; from p0 = 5 the answer is the same.
    @test isapprox(best_price(p -> 10 - p, 2.0; p0 = 5.0), 6.0; atol = TOL)
end

@testset "gradient-ad" begin
    # Forward-mode AD evaluates q on ForwardDiff.Dual numbers; finite
    # differences would call it only with Float64.
    seen = DataType[]
    q(p) = (push!(seen, typeof(p)); 100 * exp(-0.5 * p))
    p = best_price(q, 2.0)
    @test isapprox(p, 4.0; atol = TOL)
    @test any(T -> T <: ForwardDiff.Dual, seen)
end
