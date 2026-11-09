# Correct code and tests that cover milestone 1.
using Production, Test

# HiGHS's primal feasibility tolerance is 1e-7: units may be off by that much,
# profits by the margins times that.
const FEAS = 1e-7

@testset "plan" begin
    # max 4x1 + 3x2, x1 + x2 <= 5, 2x1 + x2 <= 8: vertices (0,0) (4,0) (3,2) (0,5),
    # profits 0, 16, 18, 15.
    u = [1.0 1.0; 2.0 1.0]
    r = solve_plan([4.0, 3.0], u, [5.0, 8.0])
    @test isapprox(r.units, [3.0, 2.0]; atol = FEAS)
    @test isapprox(r.profit, 18.0; atol = 10FEAS)
    @test all(u * r.units .<= [5.0, 8.0] .+ FEAS)
end

@testset "constraints are by row" begin
    # x1 + 4x2 <= 8, 2x1 + x2 <= 9 with margins (1, 1): optimum (4, 1).
    # Columns as rows would give x1 + 2x2 <= 8, 4x1 + x2 <= 9, optimum (10/7, 23/7),
    # which needs 14.6 of the first resource.
    u = [1.0 4.0; 2.0 1.0]
    r = solve_plan([1.0, 1.0], u, [8.0, 9.0])
    @test all(u * r.units .<= [8.0, 9.0] .+ FEAS)
end

@testset "no negative units" begin
    # x1 <= 5 and x1 + x2 <= 3: with x2 = -2 the profit 3*5 - 2 = 13 would beat 9.
    r = solve_plan([3.0, 1.0], [1.0 0.0; 1.0 1.0], [5.0, 3.0])
    @test minimum(r.units) >= -FEAS
end

@testset "no optimum" begin
    @test_throws ErrorException solve_plan([2.0, 1.0], [1.0 0.0], [3.0])
end
