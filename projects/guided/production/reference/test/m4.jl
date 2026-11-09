# Exemplary student tests, milestone 4: best_price.
# atol = 1e-8: LBFGS stops at |gradient| <= 1e-8 (Optim's default), and the
# price error is about that divided by the curvature at the optimum: 2 for
# the quadratic below, 100 * 0.5 * exp(-2) ≈ 6.8 for the exponential case,
# so both errors are below 5e-9.
using ForwardDiff

@testset "best_price" begin
    # (p - c) a exp(-b p) has derivative a exp(-b p) (1 - b (p - c)): zero at c + 1 / b.
    @test isapprox(best_price(100.0, 0.5, 2.0), 4.0; atol = 1e-8)
    # Linear demand 12 - p with cost 2: (p - 2)(12 - p) is largest at p = 7.
    @test isapprox(best_price(p -> 12 - p, 2.0), 7.0; atol = 1e-8)
    # The demand curve is differentiated by ForwardDiff, so it sees dual numbers.
    types = DataType[]
    best_price(p -> (push!(types, typeof(p)); 12 - p), 2.0)
    @test any(T -> T <: ForwardDiff.Dual, types)
end
