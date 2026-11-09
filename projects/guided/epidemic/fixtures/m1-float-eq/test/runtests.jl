# Correct code and good tests, but floats compared with == inside @test (checker JT006).
using Epidemic, Test

allocs(u, p) = (du = zeros(3); sir!(du, u, p, 0.0); @allocated sir!(du, u, p, 0.0))

@testset "sir!" begin
    du = zeros(3)
    @test sir!(du, [0.5, 0.5, 0.0], (1.0, 0.5), 0.0) === nothing
    @test du[1] == -0.25          # exact in binary, but still a float ==
    @test du[3] == 0.25
    @test isapprox(du[2], 0.0; atol = 1e-15)
    sir!(du, [0.6, 0.3, 0.1], (1.5, 0.25), 0.0)
    @test isapprox(du, [-0.27, 0.195, 0.075]; rtol = 1e-13)
    @test allocs([0.6, 0.3, 0.1], (1.5, 0.25)) == 0
end

@testset "simulate" begin
    p, u0 = (0.5, 0.2), [0.99, 0.01, 0.0]
    U = simulate(p, u0, 0:40)
    @test size(U) == (3, 41)
    @test U[1, 1] == 0.99
    V = simulate(p, u0, [20.0, 40.0])
    @test isapprox(V[:, 2], U[:, end]; rtol = 1e-8)
    # log(S/S0) + (beta/gamma) R = 0 exactly; ~1e-10 at these tolerances, ~1e-4 at the defaults
    @test maximum(abs, log.(U[1, :] ./ 0.99) .+ 2.5 .* U[3, :]) < 1e-8
end
