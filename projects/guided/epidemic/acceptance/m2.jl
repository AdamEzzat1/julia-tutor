# Acceptance, milestone 2: conservation and the peak. One @testset per behaviour id.
using Epidemic, Test

@testset "conservation" begin
    # The three rates sum to zero and a Runge-Kutta step preserves linear
    # invariants exactly, so S + I + R changes only by rounding: a few eps per
    # step over some hundreds of steps, ~1e-13 at most (observed 8.9e-16 for
    # the first case). 1e-9 is far above that; a right-hand side whose rates
    # do not sum to zero misses by more than 1e-3 over a year.
    for (p, u0) in (((0.5, 0.2), [0.99, 0.01, 0.0]), ((1.2, 0.4), [0.7, 0.2, 0.1]))
        U = simulate(p, u0, 0:365)
        @test maximum(abs, sum(U; dims = 1) .- sum(u0)) <= 1e-9
    end
end

@testset "peak-condition" begin
    # At the event the solver locates the root of beta S - gamma to near
    # machine precision in t; S there carries the solve's error, observed at
    # most 4.5e-11 over these four cases (abstol = reltol = 1e-10). A peak
    # rounded to whole days misses by |dS/dt| / 2, about 1e-2.
    u0 = [0.99, 0.01, 0.0]
    for p in ((0.5, 0.2), (0.3, 0.1), (1.2, 0.4), (0.45, 0.17))
        beta, gamma = p
        t = peak_day(p, u0)
        @test t isa Float64
        @test 0 < t < 365
        X = simulate(p, u0, [t])
        rho = gamma / beta
        @test abs(X[1, 1] - rho) <= 1e-6
        # I + S - rho log S is constant along the exact solution, so the peak
        # height is I0 + S0 - rho (1 + log(S0 / rho)); observed error 3e-13.
        @test abs(X[2, 1] - (u0[1] + u0[2] - rho * (1 + log(u0[1] / rho)))) <= 1e-6
    end
end

@testset "peak-none" begin
    @test iszero(peak_day((0.1, 0.2), [0.99, 0.01, 0.0]))
    @test peak_day((0.1, 0.2), [0.99, 0.01, 0.0]) isa Float64
    @test iszero(peak_day((0.3, 0.4), [0.9, 0.1, 0.0]; horizon = 100))
end
