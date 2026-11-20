# Hidden acceptance tests, milestone 2 (stage 2 adds: theta_step,
# solve_heat, fit_order). Other problems than the visible tests; every
# tolerance derived in a comment; nothing is random.

using Test
using Heat1D

const EPS = eps(Float64)

@testset "theta-step-exact-in-time" begin
    # u(x, t) = 3t + 1 solves u_t = 2 u_xx + 3 with boundary values 3t + 1.
    # Each theta reproduces it (one tridiagonal solve: 16 eps) only if the
    # boundary values move to the new time and the source is split
    # theta / (1 - theta) (here constant, so any split is right).
    N, dx, dt = 15, 1 / 16, 0.01
    p = HeatProblem(2.0, x -> 1.0, (x, t) -> 3.0, t -> 3t + 1, t -> 3t + 1)
    w = ThetaWork(N)
    for th in (0.0, 0.3, 0.5, 1.0)
        @test isapprox(theta_step!(zeros(N), fill(1.6, N), p, 0.2, dt, dx, th, w), fill(1.63, N); rtol = 16EPS)
    end
    # The source split: s = t (u = t^2 / 2 constant in x, boundary values t^2/2).
    # Crank-Nicolson integrates s = t exactly (the trapezoid rule on a line).
    q = HeatProblem(1.0, x -> 0.0, (x, t) -> t, t -> t^2 / 2, t -> t^2 / 2)
    @test isapprox(theta_step!(zeros(N), fill(0.5, N), q, 1.0, 0.5, dx, 0.5, w), fill(1.125, N); rtol = 16EPS)
end

@testset "time-loop-cost-and-method" begin
    # Cost is grid-point updates; :cn is order 2 in time and :be order 1 on
    # the manufactured problem (N = 31, against a fine CN run, 8 ... 64
    # steps over t = 1: windows +- 0.15, measured within 0.01).
    p, _ = mms_problem(0.5)
    @test last(solve_heat(p, 31, 7, 0.2; method = :be)) == 31 * 7
    ref = solve_heat(p, 31, 2^14, 1.0; method = :cn)[2]
    ns = [8, 16, 32, 64]
    for (m, order) in ((:cn, 2), (:be, 1))
        errs = [maximum(abs, solve_heat(p, 31, n, 1.0; method = m)[2] .- ref) for n in ns]
        @test order - 0.15 <= fit_order(1 ./ ns, errs) <= order + 0.15
    end
    # It ends at T: u = t with source 1 after 7 steps to T = 0.7 (16 eps per
    # step, 7 steps).
    r = HeatProblem(1.0, x -> 0.0, (x, t) -> 1.0, t -> t, t -> t)
    @test isapprox(solve_heat(r, 9, 7, 0.7; method = :cn)[2], fill(0.7, 9); rtol = 1e-13)
    @test_throws ArgumentError solve_heat(r, 9, 0, 0.7)
end

@testset "fit-least-squares" begin
    # The least-squares slope, recomputed; not the end-point slope.
    hs = [0.5, 0.2, 0.05, 0.01]
    errs = [0.3, 0.02, 0.01, 1e-5]
    x, y = log.(hs), log.(errs)
    xm, ym = sum(x) / 4, sum(y) / 4
    ls = sum((x .- xm) .* (y .- ym)) / sum(abs2, x .- xm)
    @test isapprox(fit_order(hs, errs), ls; rtol = 1e-12)
    @test !isapprox(fit_order(hs, errs), (y[4] - y[1]) / (x[4] - x[1]); rtol = 0.01)
end
