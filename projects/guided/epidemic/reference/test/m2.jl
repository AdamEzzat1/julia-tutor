# Exemplary student tests, milestone 2: facts the model must satisfy.

@testset "conservation" begin
    # Rates sum to zero; a Runge-Kutta step keeps linear invariants exactly,
    # so only rounding (a few eps per step) remains: 1e-9 is a wide bound.
    u0 = [0.98, 0.02, 0.0]
    U = simulate((0.4, 0.1), u0, 0:365)
    @test maximum(abs, sum(U; dims = 1) .- sum(u0)) <= 1e-9
end

@testset "peak" begin
    u0 = [0.98, 0.02, 0.0]
    for p in ((0.4, 0.1), (0.9, 0.3))
        rho = p[2] / p[1]
        t = peak_day(p, u0)
        X = simulate(p, u0, [t])
        # dI/dt = I (beta S - gamma) = 0 there. The event is located to near
        # machine precision; S carries the solve's error (~1e-10). A whole-day
        # answer misses by |dS/dt| / 2 ~ 1e-2.
        @test abs(X[1, 1] - rho) <= 1e-6
        # I + S - rho log S is conserved, which gives the peak height.
        @test abs(X[2, 1] - (u0[1] + u0[2] - rho * (1 + log(u0[1] / rho)))) <= 1e-6
    end
    @test iszero(peak_day((0.1, 0.3), u0))           # I never grows
end
