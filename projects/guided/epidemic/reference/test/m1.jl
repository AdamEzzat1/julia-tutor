# Exemplary student tests, milestone 1: the right-hand side and simulate.

# In a function (at top level globals would box); the first call compiles sir!.
allocs(u, p) = (du = zeros(3); sir!(du, u, p, 0.0); @allocated sir!(du, u, p, 0.0))

@testset "sir!" begin
    du = zeros(3)
    # beta = 0.4, gamma = 0.1, (S, I, R) = (0.8, 0.15, 0.05):
    # infection 0.4 * 0.8 * 0.15 = 0.048, recovery 0.1 * 0.15 = 0.015.
    @test sir!(du, [0.8, 0.15, 0.05], (0.4, 0.1), 0.0) === nothing
    @test du ≈ [-0.048, 0.033, 0.015] rtol = 1e-14   # two or three roundings per entry
    @test allocs([0.8, 0.15, 0.05], (0.4, 0.1)) == 0
end

@testset "simulate" begin
    p, u0 = (0.4, 0.1), [0.98, 0.02, 0.0]
    U = simulate(p, u0, 0:30)
    @test size(U) == (3, 31)
    @test U[:, 1] ≈ u0 rtol = 0                       # day 0 is u0 itself
    V = simulate(p, u0, [10.0, 30.0])                 # not starting at day 0
    @test size(V) == (3, 2)
    @test V[:, 2] ≈ U[:, 31] rtol = 1e-8              # same solve tolerances, saved at day 30
    # Invariant of the exact solution: log(S/S0) + (beta/gamma)(R - R0) = 0.
    # Observed ~1e-10 at abstol = reltol = 1e-10, ~1e-4 at the solver's
    # defaults (calibrated, p = (0.5, 0.2)); 1e-8 separates the two.
    @test maximum(abs, log.(U[1, :] ./ u0[1]) .+ (p[1] / p[2]) .* U[3, :]) <= 1e-8
    @test maximum(abs, log.(V[1, :] ./ u0[1]) .+ (p[1] / p[2]) .* V[3, :]) <= 1e-8
end
