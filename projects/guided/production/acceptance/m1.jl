# Acceptance, milestone 1: solve_plan. One @testset per behaviour id.
#
# Tolerance: HiGHS's primal feasibility tolerance is 1e-7 (its default), so
# a reported vertex may sit up to ~1e-7 outside a constraint and its
# coordinates may be off by that much. TOL = 1e-7 is that tolerance; the
# data below are small integers whose vertices HiGHS finds exactly in
# practice (observed error 0.0), and every wrong plan seeded in mutants.toml
# is off by 0.2 or more.
using Production, Test

const TOL = 1e-7

# Hand-solved case (Hillier and Lieberman's two-product example):
# max 3x1 + 5x2  s.t.  x1 <= 4,  2x2 <= 12,  3x1 + 2x2 <= 18,  x >= 0.
# Vertices (0,0), (4,0), (4,3), (2,6), (0,6); profits 0, 12, 27, 36, 30: (2, 6) wins.
const M = [3.0, 5.0]
const U = [1.0 0.0; 0.0 2.0; 3.0 2.0]
const C = [4.0, 12.0, 18.0]

@testset "plan-optimal" begin
    r = solve_plan(M, U, C)
    @test keys(r) == (:units, :profit)
    @test length(r.units) == 2
    @test isapprox(r.units, [2.0, 6.0]; atol = TOL)
    @test isapprox(r.profit, 36.0; atol = TOL * 10)   # 3 * 2 + 5 * 6, each unit off by at most TOL
    # One resource, two products: all of it goes to the better margin per unit of resource.
    # 2x1 + x2 <= 10 with margins (5, 3): x1 earns 2.5 per unit of resource, x2 earns 3.
    r2 = solve_plan([5.0, 3.0], reshape([2.0, 1.0], 1, 2), [10.0])
    @test isapprox(r2.units, [0.0, 10.0]; atol = TOL)
    @test isapprox(r2.profit, 30.0; atol = TOL * 10)
end

@testset "plan-feasible" begin
    for (m, u, c) in ((M, U, C),
                      # x1 + 2x2 <= 8, 3x1 + x2 <= 9: optimum (2, 3). Swapping the
                      # indices of `use` gives (3.8, 1.4), which breaks 3x1 + x2 <= 9.
                      ([1.0, 1.0], [1.0 2.0; 3.0 1.0], [8.0, 9.0]),
                      # x1 <= 5, x1 + x2 <= 3 with margins (3, 1): optimum (3, 0). Without
                      # x >= 0 the LP is bounded and its optimum is (5, -2).
                      ([3.0, 1.0], [1.0 0.0; 1.0 1.0], [5.0, 3.0]))
        r = solve_plan(m, u, c)
        @test all(>=(-TOL), r.units)
        @test all(u * r.units .<= c .+ TOL)
    end
    @test isapprox(solve_plan([1.0, 1.0], [1.0 2.0; 3.0 1.0], [8.0, 9.0]).units, [2.0, 3.0]; atol = TOL)
    @test isapprox(solve_plan([3.0, 1.0], [1.0 0.0; 1.0 1.0], [5.0, 3.0]).units, [3.0, 0.0]; atol = TOL)
end

@testset "plan-status" begin
    # Product 2 earns 1 per unit and uses nothing: the profit is unbounded.
    @test_throws ErrorException solve_plan([1.0, 1.0], [1.0 0.0], [1.0])
    # A negative capacity with x >= 0 and use >= 0: no plan is feasible.
    @test_throws ErrorException solve_plan([1.0], reshape([1.0], 1, 1), [-1.0])
end
