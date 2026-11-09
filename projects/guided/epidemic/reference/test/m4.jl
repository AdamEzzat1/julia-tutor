# Exemplary student tests, milestone 4: golden-section search and the fit.

@testset "golden_section" begin
    calls = Ref(0)
    f = x -> (calls[] += 1; (x - 0.7)^2)   # no constant offset: resolvable to tol
    x = golden_section(f, 0.0, 2.0; tol = 1e-9)
    @test abs(x - 0.7) <= 1e-9
    # One evaluation per step after the first two: log(1e-9 / 2) / log(0.618) ≈ 44.6.
    @test calls[] <= 48
    @test abs(golden_section(x -> (x + 3)^2, -5.0, 1.0) + 3) <= 1e-8   # default tol
end

@testset "fit" begin
    truth = (beta = 0.45, gamma = 0.17)   # gamma between the grid points 0.15 and 0.2
    grid = 0.05:0.05:0.5
    # Noise-free: searches stop at 1e-6 per rate; calibrated relative error 2e-6.
    f = fit(expected_cases(truth, 50); beta_range = (0.2, 1.0), gamma_grid = grid)
    @test f.beta ≈ truth.beta rtol = 1e-4
    @test f.gamma ≈ truth.gamma rtol = 1e-4
    # The shipped data (seed and rates in the reading); 5% is the calibrated bound.
    y = open(read_cases, joinpath(@__DIR__, "..", "data", "cases.csv"))
    g = fit(y; beta_range = (0.2, 1.0), gamma_grid = grid)
    @test g.beta ≈ truth.beta rtol = 0.05
    @test g.gamma ≈ truth.gamma rtol = 0.05
end
