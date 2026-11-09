# Acceptance, milestone 1: sir! and simulate. One @testset per behaviour id.
using Epidemic, Test, DifferentialEquations

# Allocation is measured inside a function (at top level the globals would box).
rhs_allocs(du, u, p) = @allocated sir!(du, u, p, 0.0)

@testset "rhs-values" begin
    du = zeros(3)
    u = [0.9, 0.08, 0.02]
    @test sir!(du, u, (0.5, 0.2), 0.0) === nothing
    # beta S I = 0.036, gamma I = 0.016. Two or three rounded operations per
    # entry: rtol 1e-14 is a wide margin over a few eps.
    @test isapprox(du, [-0.036, 0.036 - 0.016, 0.016]; rtol = 1e-14)
    # Different numbers so a swap of beta and gamma, or of S and I, shows.
    sir!(du, [0.6, 0.3, 0.1], [1.5, 0.25], 0.0)
    @test isapprox(du, [-0.27, 0.27 - 0.075, 0.075]; rtol = 1e-14)
    @test isapprox(u, [0.9, 0.08, 0.02]; rtol = 0)   # u is read, not written
    rhs_allocs(du, u, (0.5, 0.2))                  # compile first
    @test rhs_allocs(du, u, (0.5, 0.2)) == 0
end

# Independent truth: our own right-hand side, solved with Vern9 at 1e-14.
function truth(p, u0, days)
    f!(du, u, q, t) = (du[1] = -q[1] * u[1] * u[2];
                       du[2] = q[1] * u[1] * u[2] - q[2] * u[2];
                       du[3] = q[2] * u[2]; nothing)
    prob = ODEProblem(f!, collect(Float64, u0), (0.0, Float64(last(days))), p)
    return Array(solve(prob, Vern9(); saveat = days, abstol = 1e-14, reltol = 1e-14))
end

@testset "simulate-saveat" begin
    p, u0 = (0.5, 0.2), [0.99, 0.01, 0.0]
    U = simulate(p, u0, 0:10)
    @test U isa Matrix{Float64}
    @test size(U) == (3, 11)
    @test isapprox(U[:, 1], u0; rtol = 0)            # day 0 is the initial state, copied
    # Days that do not start at 0: still counted from day 0.
    days = [5.0, 10.0, 20.0]
    V = simulate(p, u0, days)
    @test size(V) == (3, 3)
    # Tolerance (calibrated: p = (0.5, 0.2), u0 above, days 0:365, observed
    # max abs error 1.3e-10 with abstol = reltol = 1e-10; the solver's default
    # tolerances give 3.2e-5): 1e-8 is 77x the first and 3000x below the second.
    @test maximum(abs, V .- truth(p, u0, days)) <= 1e-8
    W = simulate(p, u0, 0:365)
    @test maximum(abs, W .- truth(p, u0, 0:365)) <= 1e-8
    # The SIR invariant log(S/S0) + (beta/gamma) (R - R0) = 0 of the exact
    # solution (calibrated as above: observed 9.6e-11 at 1e-10, 1.2e-4 at the
    # defaults).
    @test maximum(abs, log.(W[1, :] ./ u0[1]) .+ (p[1] / p[2]) .* W[3, :]) <= 1e-8
end
