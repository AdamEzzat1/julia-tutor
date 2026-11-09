# Exemplary student tests, milestone 3: break_even.
# atol = 1e-6: HiGHS counts a reduced cost within 1e-7 (its dual
# feasibility tolerance) as zero, so the jump it shows can be ~1e-7 off;
# 1e-6 is ten times that. For larger margins the tolerance scales with them.

@testset "break_even" begin
    # One resource: 2x1 + x2 <= 10. Product 2 earns m2 per unit of resource,
    # product 1 earns m1 / 2: product 1 is made once m1 > 2 m2.
    u, c = reshape([2.0, 1.0], 1, 2), [10.0]
    @test isapprox(break_even([1.0, 2.0], u, c), 4.0; atol = 1e-6)
    # The same for product 2 against product 1 at margin 6: m2 > 6 / 2 = 3.
    @test isapprox(break_even([6.0, 1.0], u, c; product = 2), 3.0; atol = 1e-6)
    # A large break-even margin, far above any small fixed bracket: 2 * 40 = 80.
    @test isapprox(break_even([1.0, 40.0], u, c), 80.0; atol = 80e-6)
    # Product 1 needs a resource there is none of: never made.
    @test isinf(break_even([1.0, 1.0], [1.0 1.0; 1.0 0.0], [10.0, 0.0]))
end
