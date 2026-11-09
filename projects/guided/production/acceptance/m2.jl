# Acceptance, milestone 2: shadow_prices. One @testset per behaviour id.
#
# Tolerance: HiGHS's dual feasibility tolerance is 1e-7 (its default), so a
# reported dual may be off by up to ~1e-7; TOL = 1e-7 is that tolerance
# (observed error 0.0 on these small integer cases). For the re-solve check
# the profit difference of two solves, each within ~1e-6 of exact (TOL times
# margins of size <= 5 and units of size <= 10), is divided by DELTA = 0.5,
# so the quotient is within 4e-6 of the price: RESOLVE_TOL = 1e-5.
using Production, Test

const TOL = 1e-7
const DELTA = 0.5
const RESOLVE_TOL = 1e-5

# Hand-solved: max 3x1 + 5x2 s.t. x1 <= 4, 2x2 <= 12, 3x1 + 2x2 <= 18. The
# optimum (2, 6) makes resources 2 and 3 binding; solving 3 = y3 * 3 and
# 5 = 2 y2 + 2 y3 gives y = (0, 1.5, 1). Resource 1 has slack 2: price 0.
const M = [3.0, 5.0]
const U = [1.0 0.0; 0.0 2.0; 3.0 2.0]
const C = [4.0, 12.0, 18.0]

@testset "shadow-prices" begin
    y = shadow_prices(M, U, C)
    @test length(y) == 3
    @test all(>=(-TOL), y)
    @test isapprox(y, [0.0, 1.5, 1.0]; atol = TOL)
    # Re-solve with one more half unit of each resource: the vertex stays the
    # same kind (DELTA = 0.5 keeps x1 = (18 - c2) / 3 > 0 and x1 < 4), so the
    # profit grows by exactly price * DELTA.
    base = solve_plan(M, U, C).profit
    for r in 1:3
        c = copy(C)
        c[r] += DELTA
        @test isapprox((solve_plan(M, U, c).profit - base) / DELTA, y[r]; atol = RESOLVE_TOL)
    end
    # One resource, two products: x2 = 10 uses all of it, worth 3 per unit.
    @test isapprox(shadow_prices([5.0, 3.0], reshape([2.0, 1.0], 1, 2), [10.0]), [3.0]; atol = TOL)
end
