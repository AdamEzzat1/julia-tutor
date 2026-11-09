# Acceptance, milestone 3: break_even. One @testset per behaviour id.
#
# Tolerance: the jump of units(m) is where the product's reduced cost
# changes sign. HiGHS treats a reduced cost within its dual feasibility
# tolerance (1e-7) as zero, so the jump it shows can sit up to ~1e-7 away
# from the exact margin (observed: 1e-7 above it). Bisection itself closes
# to a few ulps. TOL = 1e-6 is 10x the solver's tolerance; every wrong
# answer seeded in mutants.toml is off by 1 or more.
using Production, Test

const TOL = 1e-6

# Two products, two resources: 2x1 + x2 <= 10, x1 + x2 <= 8.
# Without product 1, x2 = 8 uses resource 2 up (price = margin of product 2)
# and leaves resource 1 slack (price 0). Product 1 enters once its margin
# beats what its resources earn there: 0 * 2 + margin2 * 1 = margin2.
const U = [2.0 1.0; 1.0 1.0]
const C = [10.0, 8.0]

@testset "break-even" begin
    @test isapprox(break_even([1.0, 3.0], U, C), 3.0; atol = TOL)
    # The margin of product 1 that is passed in does not matter: it is the unknown.
    @test isapprox(break_even([7.0, 3.0], U, C), 3.0; atol = TOL)
    # Product 2 with product 1 at margin 3: without product 2, x1 = 5 uses
    # resource 1 up, priced 3 / 2 = 1.5; product 2 needs one unit of it.
    @test isapprox(break_even([3.0, 1.0], U, C; product = 2), 1.5; atol = TOL)
    @test break_even([1.0, 3.0], U, C) isa Float64
end

@testset "break-even-bracket" begin
    # Break-even margins of 30 and 250: a fixed bracket such as [0, 10] misses them.
    @test isapprox(break_even([1.0, 30.0], U, C), 30.0; atol = TOL)
    @test isapprox(break_even([1.0, 250.0], U, C), 250.0; atol = TOL * 250)   # relative: the solver's tolerances scale with the margins
end

@testset "never-made" begin
    # Resource 2 has capacity 0 and product 1 needs it: product 1 is never made.
    r = break_even([1.0, 1.0], [1.0 1.0; 1.0 0.0], [10.0, 0.0])
    @test r isa Float64
    @test isinf(r) && r > 0
end
