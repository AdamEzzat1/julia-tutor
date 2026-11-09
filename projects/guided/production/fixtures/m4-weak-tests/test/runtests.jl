# Correct code; the tests check the prices only (never how the gradient was
# computed), and one compares a float profit with ==.
using Production, Test

@testset "plan" begin
    u, c = [1.0 0.0; 0.0 2.0; 3.0 2.0], [4.0, 12.0, 18.0]
    r = solve_plan([3.0, 5.0], u, c)
    @test r.profit == 36.0
    @test isapprox(r.units, [2.0, 6.0]; atol = 1e-7)   # HiGHS's feasibility tolerance
    @test all(u * r.units .<= c .+ 1e-7)
    @test minimum(solve_plan([3.0, 1.0], [1.0 0.0; 1.0 1.0], [5.0, 3.0]).units) >= -1e-7
    @test isapprox(solve_plan([1.0, 1.0], [1.0 3.0; 2.0 1.0], [9.0, 8.0]).units, [3.0, 2.0]; atol = 1e-7)
    @test_throws ErrorException solve_plan([1.0, 1.0], [1.0 0.0], [1.0])
    # Dual feasibility tolerance 1e-7.
    @test isapprox(shadow_prices([3.0, 5.0], u, c), [0.0, 1.5, 1.0]; atol = 1e-7)
end

@testset "break even" begin
    # 2x1 + x2 <= 10: made once m1 > 2 m2. atol: ten times the 1e-7 dual tolerance.
    u, c = reshape([2.0, 1.0], 1, 2), [10.0]
    @test isapprox(break_even([1.0, 2.0], u, c), 4.0; atol = 1e-6)
    @test isapprox(break_even([6.0, 1.0], u, c; product = 2), 3.0; atol = 1e-6)
    @test isapprox(break_even([1.0, 40.0], u, c), 80.0; atol = 80e-6)
    @test isinf(break_even([1.0, 1.0], [1.0 1.0; 1.0 0.0], [10.0, 0.0]))
end

@testset "price" begin
    # Optim's gradient tolerance 1e-8 over a curvature of about 7 (and 2).
    @test isapprox(best_price(100.0, 0.5, 2.0), 4.0; atol = 1e-8)
    @test isapprox(best_price(p -> 12 - p, 2.0), 7.0; atol = 1e-8)
end
