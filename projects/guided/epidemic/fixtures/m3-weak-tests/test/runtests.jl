# Correct code; good tests for milestones 1 and 2, but milestone 3 is tested
# only for shape and for the minimum at the truth, which squared errors, the
# mean of the terms and a prevalence curve also satisfy.
using Epidemic, Test

allocs(u, p) = (du = zeros(3); sir!(du, u, p, 0.0); @allocated sir!(du, u, p, 0.0))

@testset "milestones 1 and 2" begin
    du = zeros(3)
    @test sir!(du, [0.8, 0.15, 0.05], (0.4, 0.1), 0.0) === nothing
    @test isapprox(du, [-0.048, 0.033, 0.015]; rtol = 1e-14)   # a few roundings
    @test allocs([0.8, 0.15, 0.05], (0.4, 0.1)) == 0
    u0 = [0.98, 0.02, 0.0]
    U = simulate((0.4, 0.1), u0, 0:365)
    @test size(U) == (3, 366)
    V = simulate((0.4, 0.1), u0, [10.0, 365.0])
    @test isapprox(V[:, 2], U[:, end]; rtol = 1e-8)              # same tolerances
    # invariant of the exact solution: ~1e-10 at tolerance 1e-10, ~1e-4 at the defaults
    @test maximum(abs, log.(U[1, :] ./ u0[1]) .+ 4 .* U[3, :]) <= 1e-8
    @test maximum(abs, sum(U; dims = 1) .- 1) <= 1e-9           # RK keeps linear invariants
    t = peak_day((0.4, 0.1), u0)
    @test abs(simulate((0.4, 0.1), u0, [t])[1] - 0.25) <= 1e-6   # S = gamma / beta, error ~1e-10
    @test iszero(peak_day((0.1, 0.3), u0))
end

@testset "milestone 3" begin
    y = read_cases(IOBuffer("day,cases\n1,3\n2,5\n"))
    @test length(y) == 2
    clean = expected_cases((0.5, 0.2), 30)
    @test length(clean) == 30
    @test loss((0.5, 0.2), clean) < loss((0.55, 0.2), clean)
end
