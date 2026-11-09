using Epidemic, Test

count_allocs(u, p) = (du = similar(u); sir!(du, u, p, 0.0); @allocated sir!(du, u, p, 0.0))

@testset "right-hand side" begin
    du = zeros(3)
    # 0.6 * 0.5 * 0.2 = 0.06 infected, 0.25 * 0.2 = 0.05 recovered per day
    @test isnothing(sir!(du, [0.5, 0.2, 0.3], [0.6, 0.25], 0.0))
    @test isapprox(du, [-0.06, 0.01, 0.05]; rtol = 1e-13)   # a couple of roundings
    @test count_allocs([0.5, 0.2, 0.3], [0.6, 0.25]) == 0
end

@testset "simulate" begin
    p = (0.6, 0.25)
    u0 = [0.95, 0.05, 0.0]
    U = simulate(p, u0, 0:20)
    @test size(U) == (3, 21)
    late = simulate(p, u0, [15.0, 20.0])
    @test size(late) == (3, 2)
    @test isapprox(late[:, 2], U[:, end]; rtol = 1e-8)      # both at tolerance 1e-10
    # S = S0 exp(-(beta/gamma) R) exactly; at tolerance 1e-10 this holds to ~1e-10,
    # with the default tolerances only to ~1e-4.
    @test all(abs.(log.(U[1, :] / 0.95) + 2.4 * U[3, :]) .< 1e-8)
end

@testset "conservation" begin
    # A Runge-Kutta method keeps S + I + R exactly apart from rounding.
    U = simulate((0.6, 0.25), [0.95, 0.05, 0.0], 0:365)
    @test all(abs.(sum(U; dims = 1) .- 1) .< 1e-9)
end

@testset "peak" begin
    for p in ((0.6, 0.25), (0.35, 0.1))
        t = peak_day(p, [0.95, 0.05, 0.0])
        S = simulate(p, [0.95, 0.05, 0.0], [t])[1]
        @test abs(S - p[2] / p[1]) < 1e-6    # error ~1e-10; a whole day would be ~1e-2 off
    end
    @test iszero(peak_day((0.2, 0.25), [0.95, 0.05, 0.0]))
end
