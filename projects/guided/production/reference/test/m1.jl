# Exemplary student tests, milestone 1: solve_plan.
# atol = 1e-7: HiGHS's default primal feasibility tolerance, the most a
# vertex it reports may be off by; profits get 10x that (margins up to 5
# times two units each off by 1e-7).

@testset "solve_plan" begin
    # By hand: x1 + x2 <= 4 and x1 + 3x2 <= 6 with margins (2, 3).
    # Vertices (0, 0), (4, 0), (3, 1), (0, 2); profits 0, 8, 9, 6: (3, 1) wins.
    m, u, c = [2.0, 3.0], [1.0 1.0; 1.0 3.0], [4.0, 6.0]
    r = solve_plan(m, u, c)
    @test isapprox(r.units, [3.0, 1.0]; atol = 1e-7)
    @test isapprox(r.profit, 9.0; atol = 1e-6)
    @test all(u * r.units .<= c .+ 1e-7)

    # A use matrix that is not symmetric, so reading it by columns shows:
    # x1 + 3x2 <= 9, 2x1 + x2 <= 8 (row r is resource r). Optimum (3, 2).
    # Read the other way round, the plan (1.4, 3.8) would need 12.8 of resource 1.
    u2 = [1.0 3.0; 2.0 1.0]
    r2 = solve_plan([1.0, 1.0], u2, [9.0, 8.0])
    @test all(u2 * r2.units .<= [9.0, 8.0] .+ 1e-7)
    @test isapprox(r2.units, [3.0, 2.0]; atol = 1e-7)

    # Nothing may be negative: x1 <= 5, x1 + x2 <= 3 with margins (3, 1).
    # Allowing x2 < 0 would give (5, -2) with profit 13; the real optimum is (3, 0).
    r3 = solve_plan([3.0, 1.0], [1.0 0.0; 1.0 1.0], [5.0, 3.0])
    @test all(>=(-1e-7), r3.units)
    @test isapprox(r3.profit, 9.0; atol = 1e-6)

    # A product that earns money and uses nothing: unbounded, so an error.
    @test_throws ErrorException solve_plan([1.0, 1.0], [1.0 0.0], [1.0])
end
