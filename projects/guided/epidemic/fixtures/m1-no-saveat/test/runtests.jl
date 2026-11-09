# Tests that look at values only, never at which days came back.
using Epidemic, Test

@testset "model" begin
    du = zeros(3)
    sir!(du, [0.9, 0.1, 0.0], (0.5, 0.2), 0.0)
    @test isapprox(du, [-0.045, 0.025, 0.02]; rtol = 1e-13)   # a few roundings
    U = simulate((0.5, 0.2), [0.9, 0.1, 0.0], 0:30)
    @test all(isapprox.(sum(U; dims = 1), 1; atol = 1e-9))     # RK keeps S + I + R
end
