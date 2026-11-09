# Tests that pass on this code (every break-even margin here is below 100).
using Production, Test

@testset "plan" begin
    # x1 + x2 <= 4, x1 + 3x2 <= 6, margins (2, 3): optimum (3, 1), profit 9.
    # atol 1e-7: HiGHS's feasibility tolerance.
    r = solve_plan([2.0, 3.0], [1.0 1.0; 1.0 3.0], [4.0, 6.0])
    @test isapprox(r.units, [3.0, 1.0]; atol = 1e-7)
    @test isapprox(r.profit, 9.0; atol = 1e-6)
    @test isapprox(shadow_prices([2.0, 3.0], [1.0 1.0; 1.0 3.0], [4.0, 6.0]), [1.5, 0.5]; atol = 1e-7)
end

@testset "break even" begin
    # 2x1 + x2 <= 10: product 1 is made once m1 / 2 > m2. atol 1e-6: ten times
    # HiGHS's dual feasibility tolerance.
    u, c = reshape([2.0, 1.0], 1, 2), [10.0]
    @test isapprox(break_even([1.0, 2.0], u, c), 4.0; atol = 1e-6)
    @test isapprox(break_even([6.0, 1.0], u, c; product = 2), 3.0; atol = 1e-6)
    @test isinf(break_even([1.0, 1.0], [1.0 1.0; 1.0 0.0], [10.0, 0.0]))
end
