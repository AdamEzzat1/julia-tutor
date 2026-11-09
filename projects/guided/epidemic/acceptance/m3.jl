# Acceptance, milestone 3: reading the counts, the model's new cases, the loss.
# One @testset per behaviour id.
using Epidemic, Test

@testset "read-cases" begin
    @test read_cases(IOBuffer("day,cases\n1,4\n2,0\n3,17\n")) == [4, 0, 17]
    @test read_cases(IOBuffer("day,cases\n1,4\n2,0\n3,17\n")) isa Vector{Int}
    @test read_cases(IOBuffer("day,cases\n1,9\n2,12\n\n")) == [9, 12]     # a trailing blank line
    @test_throws ArgumentError read_cases(IOBuffer("day,cases\n1,4\n2,0\n4,17\n"))
    @test_throws ArgumentError read_cases(IOBuffer("day,cases\n2,4\n3,0\n"))
    y = open(read_cases, joinpath(@__DIR__, "data", "cases.csv"))
    @test length(y) == 50
    @test y[1] == 2 && y[23] == 558 && y[50] == 13
end

@testset "expected-cases" begin
    p = (0.45, 0.17)
    mu = expected_cases(p, 40)
    @test mu isa Vector{Float64}
    @test length(mu) == 40
    S = simulate(p, U0, 0:40)[1, :]
    # The same arithmetic on the same solve: only a few roundings apart.
    @test isapprox(mu, POPULATION .* (S[1:end-1] .- S[2:end]); rtol = 1e-12)
    # Telescoping sum (rounding of 40 terms of size <= 600: ~1e-11 absolute).
    @test isapprox(sum(mu), POPULATION * (S[1] - S[end]); rtol = 1e-10)
    # Day 1 is the first day of new cases: about beta S0 I0 N = 4.5 for these rates.
    @test 3 < mu[1] < 6
end

@testset "loss-zero-at-truth" begin
    # Noise-free data (real-valued counts): the loss has its minimum exactly at
    # the true rates, so every neighbour on a 1% and 5% grid is higher. The
    # smallest gap is 1.1 in loss (calibrated, first case; 2.1 for the
    # second), far above the solve's error in the loss (~1e-10 relative in
    # mu times a loss of size ~1e4: ~1e-6).
    for p in ((0.45, 0.17), (0.6, 0.3))
        y = expected_cases(p, 50)
        L0 = loss(p, y)
        for db in (-0.05, -0.01, 0.0, 0.01, 0.05), dg in (-0.05, -0.01, 0.0, 0.01, 0.05)
            iszero(db) && iszero(dg) && continue
            @test L0 < loss((p[1] * (1 + db), p[2] * (1 + dg)), y)
        end
    end
end

@testset "loss-poisson" begin
    p = (0.45, 0.17)
    y = [3, 0, 8, 12, 9]
    mu = expected_cases(p, 5)
    # Same formula, a handful of roundings over 5 terms: rtol 1e-12.
    @test isapprox(loss(p, y), sum(mu .- y .* log.(mu)); rtol = 1e-12)
    @test loss(p, y) isa Float64
    z = open(read_cases, joinpath(@__DIR__, "data", "cases.csv"))
    m = expected_cases(p, 50)
    @test isapprox(loss(p, z), sum(m .- z .* log.(m)); rtol = 1e-12)
end
