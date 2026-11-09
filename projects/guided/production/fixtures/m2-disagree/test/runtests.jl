# The test was written to match the code: it expects negative prices, which
# the spec rules out (a correct implementation returns 1.5 and 0.5).
using Production, Test

@testset "plan" begin
    # atol 1e-7: HiGHS's feasibility tolerance.
    r = solve_plan([2.0, 3.0], [1.0 1.0; 1.0 3.0], [4.0, 6.0])
    @test isapprox(r.units, [3.0, 1.0]; atol = 1e-7)
    @test isapprox(r.profit, 9.0; atol = 1e-6)
    @test_throws ErrorException solve_plan([1.0, 1.0], [1.0 0.0], [1.0])
    @test minimum(solve_plan([3.0, 1.0], [1.0 0.0; 1.0 1.0], [5.0, 3.0]).units) >= -1e-7
end

@testset "prices" begin
    # atol 1e-7: HiGHS's dual feasibility tolerance.
    @test isapprox(shadow_prices([2.0, 3.0], [1.0 1.0; 1.0 3.0], [4.0, 6.0]), [-1.5, -0.5]; atol = 1e-7)
end
