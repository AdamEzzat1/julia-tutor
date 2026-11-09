# Acceptance, milestone 4: golden-section search and the fit. One @testset per behaviour id.
using Epidemic, Test

@testset "golden-section" begin
    # Parabolas without a constant offset: near the minimum (x - c)^2 is
    # computed to full relative precision, so the search can resolve the
    # minimiser to the bracket width (with an offset of 1 it could not get
    # below about sqrt(eps) = 1.5e-8).
    for (c, a, b, tol) in ((0.3, 0.0, 1.0, 1e-8), (-2.5, -10.0, 4.0, 1e-8), (7.0, 6.0, 9.0, 1e-6), (0.95, 0.0, 1.0, 1e-8))
        n = Ref(0)
        f = x -> (n[] += 1; (x - c)^2)
        x = golden_section(f, a, b; tol)
        @test x isa Float64
        @test abs(x - c) <= tol
        # Two first evaluations, then one per step while the bracket shrinks by
        # 0.618 per step from b - a to tol: at most ceil of the ratio of logs; +4 also
        # covers 0.618 being a rounded golden fraction.
        @test n[] <= log(tol / (b - a)) / log(0.618) + 4
    end
    @test abs(golden_section(x -> (x - 0.25)^2, 0, 1) - 0.25) <= 1e-8   # default tol, integer ends
end

const TRUE_RATES = (beta = 0.45, gamma = 0.17)
const GRID = 0.05:0.05:0.5   # the true gamma, 0.17, is between grid points

@testset "fit-recovers" begin
    # Noise-free data: the loss's minimum is at the true rates; the searches
    # stop at tol = 1e-6 in each rate. Calibrated: observed relative error
    # 2.1e-6 (gamma) and 5.4e-7 (beta); 1e-4 is a 50x margin, and a fit that
    # stops at the grid misses gamma by 0.02 / 0.17 = 12%.
    y = expected_cases(TRUE_RATES, 50)
    f = fit(y; beta_range = (0.2, 1.0), gamma_grid = GRID)
    @test f isa NamedTuple
    @test keys(f) == (:beta, :gamma)
    @test isapprox(f.beta, TRUE_RATES.beta; rtol = 1e-4)
    @test isapprox(f.gamma, TRUE_RATES.gamma; rtol = 1e-4)
    # The shipped data (Poisson draws from Xoshiro(20261109), see the reading).
    # Calibrated: on this file the reference fit gives beta 0.45326 (+0.73%)
    # and gamma 0.17206 (+1.21%). Any correct search finds the same minimum of
    # the loss up to its tolerances (~1e-5 relative), so 5% is a 4x margin on
    # this fixed file; over seeds 1 to 8 of the same simulation the gamma
    # error ranged from -3.9% to +3.9% (the sampling error, not the search's).
    z = open(read_cases, joinpath(@__DIR__, "data", "cases.csv"))
    g = fit(z; beta_range = (0.2, 1.0), gamma_grid = GRID)
    @test isapprox(g.beta, TRUE_RATES.beta; rtol = 0.05)
    @test isapprox(g.gamma, TRUE_RATES.gamma; rtol = 0.05)
end
