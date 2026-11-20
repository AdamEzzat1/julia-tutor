# Visible tests for StiffKin: the specification of every hole.
#
# What is tested, and against what:
# * the right-hand side at hand-computed points, and mass conservation;
# * the Jacobian against central differences (exact on a quadratic, up to
#   rounding) and its zero column sums;
# * the pivoted solve on systems that need the pivot;
# * both steps on y' = lambda y against their stability functions' known
#   properties (Taylor terms, L-stability) and their local error orders;
# * the controller: lands on T, counts its work, rejects, stops on a blow-up;
# * Robertson at t = 40 against the published value.
# Nothing is random.

using Test
using StiffKin

const EPS = eps(Float64)

@testset "rhs: Robertson's equations conserve mass" begin
    # y = (1, 0, 0): only A -> B runs, at rate 0.04 (exact).
    @test isequal(rhs([1.0, 0.0, 0.0], ROBERTSON), [-0.04, 0.04, 0.0])
    # y = (0.5, 1e-4, 0.5): a = 0.02, b = 1e4 * 1e-4 * 0.5 = 0.5,
    # c = 3e7 * 1e-8 = 0.3. A few roundings each: 8 eps relative.
    @test isapprox(rhs([0.5, 1e-4, 0.5], ROBERTSON), [0.48, -0.78, 0.3]; rtol = 8EPS)
    # The three components cancel: |sum| <= 4 eps times the largest term.
    for y in ([0.9, 2e-5, 0.1], [0.3, 1e-6, 0.7], [0.1, 0.2, 0.7])
        r = rhs(y, ROBERTSON)
        @test abs(sum(r)) <= 4EPS * (0.04y[1] + 1e4 * y[2] * y[3] + 3e7 * y[2]^2)
    end
    # Other rate constants are used, not Robertson's.
    @test isapprox(rhs([1.0, 1.0, 1.0], Kinetics(1.0, 2.0, 3.0)), [2.0, -4.0, 2.0]; rtol = 4EPS)
end

@testset "jacobian: against central differences, columns sum to zero" begin
    # rhs is quadratic in y, so a central difference has no truncation
    # error; its rounding error is about eps |f| / h = 2e-16 * 0.1 / 1e-8 =
    # 2e-9, far below the 1e-6 allowed here (entries reach 1.8e3).
    y = [0.7, 3e-5, 0.3]
    J = jacobian(y, ROBERTSON)
    h = 1e-8
    for j in 1:3
        e = zeros(3)
        e[j] = h
        col = (rhs(y .+ e, ROBERTSON) .- rhs(y .- e, ROBERTSON)) ./ (2h)
        @test isapprox(J[:, j], col; atol = 1e-6)
    end
    for j in 1:3
        @test abs(sum(J[:, j])) <= 8EPS * maximum(abs, J)
    end
end

@testset "solve_pivot: Gaussian elimination with partial pivoting" begin
    # A zero leading entry: only a row swap solves it (exact arithmetic).
    @test isequal(solve_pivot([0.0 1.0; 1.0 1.0], [2.0, 3.0]), [1.0, 2.0])
    # A tiny leading entry: without pivoting x1 comes out 0. The exact
    # solution is (1, 1) to 1e-20 relative; 4 eps.
    @test isapprox(solve_pivot([1e-20 1.0; 1.0 1.0], [1.0, 2.0]), [1.0, 1.0]; rtol = 4EPS)
    # A 3x3 system with a known solution; well conditioned (cond < 20): 32 eps.
    A = [2.0 -1.0 0.5; 4.0 1.0 -1.0; -1.0 3.0 2.0]
    xt = [1.0, -2.0, 0.5]
    b = A * xt
    A0, b0 = copy(A), copy(b)
    @test isapprox(solve_pivot(A, b), xt; rtol = 32EPS)
    @test isequal(A, A0) && isequal(b, b0)
    @test_throws ArgumentError solve_pivot([1.0 2.0; 2.0 4.0], [1.0, 1.0])
end

@testset "bs32_step: order 3 with a second-order error estimate" begin
    # On y' = lambda y one step multiplies by the cubic Taylor polynomial
    # of exp(z), z = lambda h (3 stages, order 3): 8 eps.
    lam = -2.0
    f(y) = lam .* y
    for h in (0.1, 0.25)
        z = lam * h
        ynew, err, nf = bs32_step(f, [1.0], h)
        @test isapprox(ynew[1], 1 + z + z^2 / 2 + z^3 / 6; rtol = 8EPS)
        @test nf == 4
    end
    # Halving h divides the local error of ynew by 2^4 = 16 and the error
    # estimate by 2^3 = 8 (leading terms; at these h the next terms change
    # the ratios by under 10%).
    loc(h) = abs(bs32_step(f, [1.0], h)[1][1] - exp(lam * h))
    est(h) = abs(bs32_step(f, [1.0], h)[2][1])
    @test 14 <= loc(0.02) / loc(0.01) <= 18
    @test 7 <= est(0.02) / est(0.01) <= 9
end

@testset "ros2_step: L-stable, order 2, exact for constant f" begin
    # Constant f: k1 = c, k2 = -c, so ynew = y + h c exactly, and the
    # first-order solution y + h c too: err = 0. J = 0 here.
    c = [1.0, -2.0, 0.5]
    ynew, err, nf, nj = ros2_step(y -> c, y -> zeros(3, 3), [1.0, 1.0, 1.0], 0.25)
    @test isapprox(ynew, [1.25, 0.5, 1.125]; rtol = 4EPS) && all(x -> abs(x) <= 4EPS, err)
    @test nf == 2 && nj == 1
    # L-stability: the factor per step goes to 0 as lambda h -> -infinity
    # (gamma = 1 + 1/sqrt(2) makes the limit exactly 0; at z = -1e8 the
    # factor is O(1/z), far below 1e-6).
    lam = -1e8
    @test abs(ros2_step(y -> lam .* y, y -> fill(lam, 1, 1), [1.0], 1.0)[1][1]) <= 1e-6
    # Halving h divides the local error by 2^3 = 8 (order 2) and the error
    # estimate by 2^2 = 4 (leading terms; within 10% at these h).
    g(y) = -2.0 .* y
    jg(y) = fill(-2.0, 1, 1)
    loc(h) = abs(ros2_step(g, jg, [1.0], h)[1][1] - exp(-2h))
    est(h) = abs(ros2_step(g, jg, [1.0], h)[2][1])
    @test 7 <= loc(0.02) / loc(0.01) <= 9
    @test 3.5 <= est(0.02) / est(0.01) <= 4.5
end

@testset "integrate: adaptive, lands on T, counts its work" begin
    # A rotation y1' = y2, y2' = -y1 over one period with BS3(2): the
    # error control is local, so the global error is a modest multiple of
    # the tolerance (measured 2e-7 at rtol 1e-6; allowed 1e-5).
    rot(y) = [y[2], -y[1]]
    T = 2pi
    y, s = integrate((y, h) -> bs32_step(rot, y, h), [1.0, 0.0], T; rtol = 1e-6, atol = 1e-9, h0 = 0.01, order = 3)
    @test isapprox(y, [cos(T), -sin(T)]; atol = 1e-5)
    @test isequal(s.t, T)
    @test s.nf == 4 * (s.steps + s.rejected) && s.nj == 0
    # A tighter tolerance gives a smaller error (by 10x for 100x, order 3).
    y2, _ = integrate((y, h) -> bs32_step(rot, y, h), [1.0, 0.0], T; rtol = 1e-8, atol = 1e-11, h0 = 0.01, order = 3)
    @test maximum(abs, y2 .- [cos(T), -sin(T)]) < maximum(abs, y .- [cos(T), -sin(T)]) / 10
    # A first step far too long is rejected, then shrunk.
    _, s2 = integrate((y, h) -> bs32_step(rot, y, h), [1.0, 0.0], 1.0; rtol = 1e-6, atol = 1e-9, h0 = 10.0, order = 3)
    @test s2.rejected >= 1 && isequal(s2.t, 1.0)
    # y' = y^2 from 1 blows up at t = 1: the step underflows and the
    # integration stops there, without an error, far short of T = 2 (the
    # discrete solution's own blow-up is within 1e-5 of t = 1: measured
    # 1.000002).
    _, s3 = integrate((y, h) -> bs32_step(y -> y .^ 2, y, h), [1.0], 2.0; rtol = 1e-6, atol = 1e-9, h0 = 0.01, order = 3)
    @test 0.99 < s3.t < 1.01
end

@testset "Robertson at t = 40: the published value, mass conserved" begin
    # The value y(40) = (0.7158270687193941, 9.185534764557338e-6,
    # 0.2841637457458413) is in the IVP test-set literature; a BS3(2) run at
    # rtol 1e-10 reproduces it to 1e-10 relative. ROS2 at rtol 1e-6 is
    # within 1e-5 of it (measured: 7.4e-7 in the worst component).
    p = ROBERTSON
    yref = [0.7158270687193941, 9.185534764557338e-6, 0.2841637457458413]
    y, s = integrate((y, h) -> ros2_step(u -> rhs(u, p), u -> jacobian(u, p), y, h), [1.0, 0.0, 0.0], 40.0;
                     rtol = 1e-6, atol = 1e-12, h0 = 1e-6, order = 2)
    @test all(abs.(y .- yref) ./ yref .<= 1e-5)
    # Both methods keep the linear invariant y1 + y2 + y3 = 1 up to the
    # rounding of each step: 1e-12 over a few thousand steps.
    @test abs(sum(y) - 1) <= 1e-12
    @test s.nj == s.steps + s.rejected && s.ymin >= 0
end

@testset "fit_order: least squares on log-log" begin
    @test isapprox(fit_order([0.1, 0.01, 0.001], [3e-2, 3e-4, 3e-6]), 2; rtol = 1e-12)
    hs = [1.0, 0.25, 0.125]
    errs = [1.0, 0.5, 1 / 64]
    x, y = log.(hs), log.(errs)
    xm, ym = sum(x) / 3, sum(y) / 3
    @test isapprox(fit_order(hs, errs), sum((x .- xm) .* (y .- ym)) / sum(abs2, x .- xm); rtol = 1e-12)
end
