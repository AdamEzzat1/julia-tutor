# Exemplary student tests, milestone 2: shadow_prices.
# atol = 1e-7: HiGHS's default dual feasibility tolerance. The re-solve
# check divides a difference of two profits (each within ~1e-6) by 0.5,
# so it gets atol = 1e-5.

@testset "shadow_prices" begin
    # x1 + x2 <= 4, x1 + 3x2 <= 6, x1 <= 10, margins (2, 3): optimum (3, 1)
    # with resources 1 and 2 binding. y1 + y2 = 2 and y1 + 3y2 = 3 give
    # y = (1.5, 0.5); resource 3 has slack 7, so its price is 0.
    m, u, c = [2.0, 3.0], [1.0 1.0; 1.0 3.0; 1.0 0.0], [4.0, 6.0, 10.0]
    y = shadow_prices(m, u, c)
    @test isapprox(y, [1.5, 0.5, 0.0]; atol = 1e-7)
    # The same by re-solving with half a unit more of resource 1: (3.75, 0.75)
    # is still the same vertex, so the profit grows by 1.5 * 0.5.
    base = solve_plan(m, u, c).profit
    more = solve_plan(m, u, [4.5, 6.0, 10.0]).profit
    @test isapprox((more - base) / 0.5, y[1]; atol = 1e-5)
end
