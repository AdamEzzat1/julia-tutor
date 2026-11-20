# Behavioural specification of Heat1D.
#
# Verification by three kinds of evidence, each tolerance derived in a
# comment (invariant 9):
# * exact solutions: a quadratic in x (the second difference is exact on
#   it) and u = t (linear in time, constant in x), which every scheme keeps
#   to rounding when its boundary values and source are taken at the right
#   times; with dyadic dx and dt the arithmetic is often exact;
# * the method of manufactured solutions: measured convergence orders in
#   space (2) and time (2 for Crank-Nicolson, 1 for backward Euler);
# * FTCS's stability limit, against von Neumann's analysis.
# Nothing is random.

using Test
using Heat1D

const EPS = eps(Float64)

@testset "second_difference: exact on quadratics, uses the boundary values" begin
    # N = 7, dx = 1/8: grid values of x^2 and 3 + x are dyadic, so the
    # differences are exact.
    N, dx = 7, 1 / 8
    x = grid(N)
    d2 = zeros(N)
    @test isequal(second_difference!(d2, x .^ 2, 0.0, 1.0, dx), fill(2.0, N))
    @test isequal(second_difference!(d2, 3 .+ x, 3.0, 4.0, dx), zeros(N))
    # The boundary values are the neighbours of the end points.
    @test isequal(second_difference!(d2, zeros(N), 1.0, 0.0, dx)[1], 64.0)
    @test isequal(second_difference!(d2, zeros(N), 0.0, 2.0, dx)[N], 128.0)
    @test isequal(second_difference!(zeros(1), [1.0], 0.0, 0.0, 0.5), [-8.0])
end

@testset "ftcs_step: one explicit step" begin
    N, dx, dt = 7, 1 / 8, 1 / 256
    x = grid(N)
    # A steady quadratic: kappa u_xx + s = 2 kappa - 2 kappa = 0, so the step keeps it exactly.
    p = HeatProblem(2.0, x -> x^2, (x, t) -> -4.0, t -> 0.0, t -> 1.0)
    unew = zeros(N)
    @test isequal(ftcs_step!(unew, x .^ 2, p, 0.0, dt, dx, zeros(N)), x .^ 2)
    # The source is taken at the old time t: s = t from t = 1/2 adds dt/2.
    q = HeatProblem(1.0, x -> 0.0, (x, t) -> t, t -> 0.0, t -> 0.0)
    @test isequal(ftcs_step!(unew, zeros(N), q, 0.5, dt, dx, zeros(N)), fill(dt / 2, N))
    # kappa multiplies the second difference: u = x(1 - x) has u_xx = -2.
    r = HeatProblem(3.0, x -> 0.0)
    ftcs_step!(unew, x .* (1 .- x), r, 0.0, dt, dx, zeros(N))
    @test isapprox(unew, x .* (1 .- x) .- 6dt; atol = 4EPS)
end

@testset "thomas: tridiagonal solve" begin
    # A diagonally dominant system with a known solution; Gaussian
    # elimination on a well-conditioned 5x5 system: error <= 16 eps * |x|.
    a = [0.0, -1.0, -2.0, -1.0, -0.5]
    b = [4.0, 5.0, 6.0, 4.0, 3.0]
    c = [-1.0, -1.0, -2.0, -1.0, 0.0]
    xt = [1.0, 2.0, 3.0, 4.0, 5.0]
    d = [b[i] * xt[i] + (i > 1 ? a[i] * xt[i-1] : 0.0) + (i < 5 ? c[i] * xt[i+1] : 0.0) for i in 1:5]
    x = zeros(5)
    thomas!(x, copy(a), copy(b), copy(c), copy(d))
    @test isapprox(x, xt; rtol = 16EPS)
    # n = 1 is a division.
    @test isequal(thomas!(zeros(1), [0.0], [4.0], [0.0], [2.0]), [0.5])
end

@testset "mms_problem: the manufactured solution solves its problem" begin
    p, ex = mms_problem(0.7)
    @test isapprox(p.u0(0.3), ex(0.3, 0.0); rtol = 4EPS)
    @test isapprox(p.left(0.4), ex(0.0, 0.4); atol = 4EPS) && isapprox(p.right(0.4), ex(1.0, 0.4); rtol = 4EPS)
    # source = u_t - kappa u_xx, checked by central differences with h = 1e-4
    # (truncation ~h^2 * |u'''| / 6 ~ 2e-8 for these derivatives of size <=
    # pi^3; rounding ~eps / h^2 ~ 2e-8 for u_xx): tolerance 1e-6.
    h = 1e-4
    for (x, t) in ((0.3, 0.2), (0.8, 1.1))
        ut = (ex(x, t + h) - ex(x, t - h)) / 2h
        uxx = (ex(x + h, t) - 2ex(x, t) + ex(x - h, t)) / h^2
        @test isapprox(p.source(x, t), ut - 0.7 * uxx; atol = 1e-6)
    end
end

@testset "theta_step: the theta method" begin
    N, dx, dt = 7, 1 / 8, 1 / 64
    x = grid(N)
    w = ThetaWork(N)
    # theta = 0 is the explicit step (same operations up to order: 4 eps).
    p, _ = mms_problem(1.0)
    u = p.u0.(x)
    @test isapprox(theta_step!(zeros(N), u, p, 0.1, dt, dx, 0.0, w), ftcs_step!(zeros(N), u, p, 0.1, dt, dx, zeros(N)); rtol = 4EPS)
    # u(x, t) = t solves u_t = u_xx + 1 with boundary values t. Each scheme
    # reproduces it if it takes the boundary values at t + dt and splits
    # the source correctly; one step from t = 1/4 gives 1/4 + dt (solving a
    # diagonally dominant system: 16 eps).
    q = HeatProblem(1.0, x -> 0.0, (x, t) -> 1.0, t -> t, t -> t)
    for th in (0.5, 1.0)
        @test isapprox(theta_step!(zeros(N), fill(0.25, N), q, 0.25, dt, dx, th, w), fill(0.25 + dt, N); rtol = 16EPS)
    end
    # The steady quadratic stays (16 eps).
    s = HeatProblem(1.0, x -> x^2, (x, t) -> -2.0, t -> 0.0, t -> 1.0)
    @test isapprox(theta_step!(zeros(N), x .^ 2, s, 0.0, 0.5, dx, 0.5, w), x .^ 2; rtol = 16EPS)
end

@testset "solve_heat: lands on T and counts its work" begin
    q = HeatProblem(1.0, x -> 0.0, (x, t) -> 1.0, t -> t, t -> t)
    for m in (:ftcs, :be, :cn)
        x, u, cost = solve_heat(q, 15, 300, 0.3; method = m)
        @test isapprox(u, fill(0.3, 15); rtol = 1e-12)      # 300 steps of 16-eps solves
        @test cost == 15 * 300
        @test length(x) == 15
    end
    @test_throws ArgumentError solve_heat(q, 15, 10, 0.3; method = :rk4)
end

@testset "convergence: order 2 in space (manufactured solution)" begin
    # CN with 4096 steps over t = 0.5 (time error ~1e-9, far below the space
    # error >= 3e-6 here), N + 1 = 16 ... 128: window 2 +- 0.1.
    p, ex = mms_problem(1.0)
    Ns = [15, 31, 63, 127]
    errs = [(r = solve_heat(p, N, 4096, 0.5; method = :cn); maximum(abs, r[2] .- ex.(r[1], 0.5))) for N in Ns]
    @test 1.9 <= fit_order(1 ./ (Ns .+ 1), errs) <= 2.1
end

@testset "convergence: order 2 (CN) and 1 (BE) in time" begin
    # Against a fine CN run on the same grid (2^14 steps), 10 ... 80 steps
    # over t = 0.5: windows 2 +- 0.1 and 1 +- 0.1 (measured 2.0005, 1.004).
    p, _ = mms_problem(1.0)
    ref = solve_heat(p, 63, 2^14, 0.5; method = :cn)[2]
    ns = [10, 20, 40, 80]
    for (m, order) in ((:cn, 2), (:be, 1))
        errs = [maximum(abs, solve_heat(p, 63, n, 0.5; method = m)[2] .- ref) for n in ns]
        @test order - 0.1 <= fit_order(0.5 ./ ns, errs) <= order + 0.1
    end
end

@testset "stability: FTCS's limit is r = 1/(2 sin^2(N pi dx / 2))" begin
    # The fastest grid mode sin(N pi x) is multiplied by 1 - 4 r sin^2(N pi
    # dx / 2) per step. 1% below the limit it decays, 1% above it grows
    # (by about 1.02^100 = 7 over 100 steps).
    N = 15
    dx = 1 / (N + 1)
    rstar = 1 / (2 * sinpi(N / 32)^2)
    mode = HeatProblem(1.0, x -> sinpi(N * x))
    amp(r) = maximum(abs, solve_heat(mode, N, 100, 100 * r * dx^2; method = :ftcs)[2])
    @test amp(0.99 * rstar) < 1
    @test amp(1.01 * rstar) > 2
    # The mode is an exact eigenvector of the discrete operator and its
    # largest grid value is sin(pi / 2) = 1, so after 100 steps the
    # amplitude is |g|^100 with g = 1 - 4 r sin^2(N pi dx / 2) (here -0.98).
    # Each step's rounding is a few eps relative and the other modes it
    # seeds decay: 1e-10 is generous. A loop that runs 99 steps is 2% off.
    g = 1 - 4 * (0.99 * rstar) * sinpi(N / 32)^2
    @test isapprox(amp(0.99 * rstar), abs(g)^100; rtol = 1e-10)
end

@testset "fit_order: least squares on log-log" begin
    @test isapprox(fit_order([0.1, 0.01, 0.001], [3e-2, 3e-4, 3e-6]), 2; rtol = 1e-12)
    hs = [1.0, 0.25, 0.125]
    errs = [1.0, 0.5, 1 / 64]
    x, y = log.(hs), log.(errs)
    xm, ym = sum(x) / 3, sum(y) / 3
    ls = sum((x .- xm) .* (y .- ym)) / sum(abs2, x .- xm)
    @test isapprox(fit_order(hs, errs), ls; rtol = 1e-12)
    @test !isapprox(fit_order(hs, errs), (y[3] - y[1]) / (x[3] - x[1]); rtol = 0.01)
    @test_throws ArgumentError fit_order([1.0], [1.0])
end
