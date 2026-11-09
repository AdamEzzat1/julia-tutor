# Exemplary student tests, milestone 3: reading counts, new cases, the loss.

@testset "read_cases" begin
    @test read_cases(IOBuffer("day,cases\n1,5\n2,7\n3,0\n")) == [5, 7, 0]
    @test_throws ArgumentError read_cases(IOBuffer("day,cases\n1,5\n2,7\n4,0\n"))
    y = open(read_cases, joinpath(@__DIR__, "..", "data", "cases.csv"))
    @test length(y) == 50
end

@testset "expected_cases" begin
    p = (0.5, 0.2)
    mu = expected_cases(p, 30)
    S = simulate(p, U0, 0:30)[1, :]
    @test length(mu) == 30
    # New cases are the fall in S each day (same solve, a few roundings).
    @test mu ≈ POPULATION .* (S[1:end-1] .- S[2:end]) rtol = 1e-12
    @test sum(mu) ≈ POPULATION * (S[1] - S[end]) rtol = 1e-10   # telescoping sum
end

@testset "loss" begin
    p = (0.5, 0.2)
    y = [4, 9, 6]
    mu = expected_cases(p, 3)
    @test loss(p, y) ≈ sum(mu .- y .* log.(mu)) rtol = 1e-12   # the formula, a few roundings
    # Noise-free data: no neighbour on a 2% grid has a lower loss (calibrated:
    # the smallest gap is 4.8, against a solve error in the loss of ~1e-6).
    clean = expected_cases(p, 40)
    L0 = loss(p, clean)
    for db in (-0.02, 0.0, 0.02), dg in (-0.02, 0.0, 0.02)
        iszero(db) && iszero(dg) && continue
        @test L0 < loss((p[1] * (1 + db), p[2] * (1 + dg)), clean)
    end
end
