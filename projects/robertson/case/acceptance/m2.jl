# Hidden acceptance tests, milestone 2 (stage 2 adds: ros2_step,
# integrate, fit_order). Other problems than the visible tests; every
# tolerance derived in a comment; nothing is random.

using Test
using StiffKin

const EPS = eps(Float64)

@testset "ros2-nonlinear-and-stiff" begin
    # y' = -y^2 with J = -2y: halving h divides the local error by 8 and the
    # estimate by 4 (leading terms; within 10% at h = 0.02, 0.01).
    f(y) = -(y .^ 2)
    jf(y) = fill(-2 * y[1], 1, 1)
    loc(h) = abs(ros2_step(f, jf, [1.0], h)[1][1] - 1 / (1 + h))
    est(h) = abs(ros2_step(f, jf, [1.0], h)[2][1])
    @test 7 <= loc(0.02) / loc(0.01) <= 9
    @test 3.5 <= est(0.02) / est(0.01) <= 4.5
    # A stiff diagonal system, rates -1e6 and -1, one step of 0.1. On a
    # linear mode with z = lambda h, the definition gives, with
    # w = 1 / (1 - gamma z): k1 = lambda w y, k2 = lambda w (1 + z w - 2 w) y,
    # so the factor is R(z) = 1 + 3/2 z w + 1/2 z w (1 + z w - 2 w). Each
    # component must follow its own R(z): a few roundings in the scalar
    # formula and in the 2x2 solve, 16 eps relative. The stiff factor is
    # O(1 / z) = 1e-5 (L-stability), a cancellation of O(1) terms: its
    # rounding is about eps / 1e-5 = 2e-11 relative, allowed 1e-9.
    A = [-1e6 0.0; 0.0 -1.0]
    y, _, _, _ = ros2_step(u -> A * u, u -> A, [1.0, 1.0], 0.1)
    g = 1 + 1 / sqrt(2)
    R(z) = (w = 1 / (1 - g * z); 1 + 1.5 * z * w + 0.5 * z * w * (1 + z * w - 2w))
    @test isapprox(y[2], R(-0.1); rtol = 16EPS)
    @test isapprox(y[1], R(-1e5); rtol = 1e-9) && abs(y[1]) <= 1e-4
end

@testset "controller-rejects-grows-lands" begin
    # A synthetic step with err = h^3 and atol = 1e-6, rtol = 0, order 3,
    # from h0 = 0.1 to T = 1: e = 1000 (rejected, factor capped at 0.2),
    # then e = 8 (rejected, factor 0.9 / 2 = 0.45), then h = 0.009, e = 0.729
    # and the factor 0.9 / 0.9 = 1: accepted at constant h, 111 steps to
    # 0.999, then the last step shortened to 0.001 to land on 1. Every
    # decision is far from its threshold (e = 0.729 against 1, and the last
    # full step ends 0.001 short of T).
    step(y, h) = (y .+ h, fill(h^3, length(y)), 1)
    y, s = integrate(step, [0.0], 1.0; rtol = 0.0, atol = 1e-6, h0 = 0.1, order = 3)
    @test s.rejected == 2 && s.steps == 112 && s.nf == 114
    @test isequal(s.t, 1.0) && isapprox(y[1], 1.0; rtol = 1e-13)
    # A zero error grows the step by 5 each time: 1e-3, 5e-3, ..., 0.625,
    # then the shortened last step: 6 steps to 1.
    z(y, h) = (y .+ h, zero(y), 1)
    _, s2 = integrate(z, [0.0], 1.0; rtol = 1e-6, atol = 1e-9, h0 = 1e-3, order = 3)
    @test s2.steps == 6 && s2.rejected == 0
    # nj is counted when the step reports it; ymin is the smallest accepted component.
    w(y, h) = (y .- h, zero(y), 2, 1)
    _, s3 = integrate(w, [1.0, 3.0], 0.5; rtol = 1e-6, atol = 1e-9, h0 = 0.5, order = 2)
    @test s3.nj == s3.steps + s3.rejected && isapprox(s3.ymin, 0.5; rtol = 4EPS)
end

@testset "controller-on-robertson-bs" begin
    # BS3(2) at rtol 1e-8 (atol 1e-14) on Robertson to t = 40 against the
    # published value: measured 1.1e-9 relative; allowed 1e-7.
    p = ROBERTSON
    yref = [0.7158270687193941, 9.185534764557338e-6, 0.2841637457458413]
    y, s = integrate((u, h) -> bs32_step(v -> rhs(v, p), u, h), [1.0, 0.0, 0.0], 40.0;
                     rtol = 1e-8, atol = 1e-14, h0 = 1e-6, order = 3)
    @test all(abs.(y .- yref) ./ yref .<= 1e-7)
    @test s.nf == 4 * (s.steps + s.rejected) && isequal(s.t, 40.0)
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
