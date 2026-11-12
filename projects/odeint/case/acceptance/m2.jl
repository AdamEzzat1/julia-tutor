# Hidden acceptance tests, milestone 2 (stage 2 adds: propose_step,
# initial_step, solve_adaptive, fit_order). Other problems than the visible
# tests; every tolerance derived in a comment; nothing is random.

using Test
using ODEInt

const EPS = eps(Float64)
const TWO_PI = 2 * pi

@testset "controller-keywords" begin
    # hnew = h * clamp(safety * en^(-1/5), facmin, facmax): <= 4 eps.
    @test isapprox(propose_step(2.0, 1.0; safety = 0.8)[2], 1.6; rtol = 4EPS)
    @test isapprox(propose_step(2.0, 1e-20; facmax = 3.0)[2], 6.0; rtol = 4EPS)
    @test isapprox(propose_step(2.0, 1e20; facmin = 0.1)[2], 0.2; rtol = 4EPS)
    @test isapprox(propose_step(1.0, 2.0^-5)[2], 1.8; rtol = 4EPS)   # 0.9 * 2
    acc, _ = propose_step(1.0, 0.999)
    @test acc
    # Accepted when en <= 1, by specification: exact at the boundary.
    @test propose_step(1.0, 1.0)[1]
    @test !propose_step(1.0, nextfloat(1.0))[1]
end

@testset "starting-step-two-components" begin
    # The DOPRI5 HINIT steps written out for y' = [-2 y1, y2], y0 = [1, 0.5],
    # atol = 1e-8, rtol = 1e-5 (independent of the student's code).
    # ~30 flops on O(1) ratios: 64 eps relative.
    f!(du, u, t) = (du[1] = -2u[1]; du[2] = u[2]; nothing)
    y0 = [1.0, 0.5]
    f0 = [-2.0, 0.5]
    atol, rtol = 1e-8, 1e-5
    sc = atol .+ rtol .* abs.(y0)
    nrm(v) = sqrt(sum((v ./ sc) .^ 2) / 2)
    d0, d1 = nrm(y0), nrm(f0)
    h0 = 0.01 * d0 / d1
    y1 = y0 .+ h0 .* f0
    f1 = [-2y1[1], y1[2]]
    d2 = nrm(f1 .- f0) / h0
    want = min(100h0, (0.01 / max(d1, d2))^(1 / 5))
    @test isapprox(initial_step(f!, 0.0, y0, f0, atol, rtol), want; rtol = 64EPS)
end

@testset "adaptive-lands-on-odd-tf" begin
    # tf = 1.2345 is not a sum of the proposed steps: the last step must be
    # shortened, and t set to tf exactly (by specification, so exact).
    f!(du, u, t) = (du[1] = -2t * u[1]^2; nothing)       # y = 1 / (1 + t^2)
    tf = 1.2345
    r = solve_adaptive(f!, [1.0], (0.0, tf); rtol = 1e-9, atol = 1e-9)
    @test r.t === tf
    @test r.nf == 2 + 6 * (r.naccept + r.nreject)
    # global error measured 0.39 tol on the reference; 10 tol leaves 25x and
    # still fails a last step that overshoots or stops short of tf.
    @test isapprox(r.y[1], 1 / (1 + tf^2); atol = 10 * 1e-9)
end

@testset "adaptive-tolerance-proportionality" begin
    # y = 1 / (1 + t^2) on [0, 5], tol = 1e-5 ... 1e-10. DOPRI5's controller
    # gives global error ~ tol (slope 1, see the visible test's derivation);
    # window [0.8, 1.25] allows the non-asymptotic end of the range.
    f!(du, u, t) = (du[1] = -2t * u[1]^2; nothing)
    tols = [10.0^-k for k in 5:10]
    errs = [abs(solve_adaptive(f!, [1.0], (0.0, 5.0); rtol = tol, atol = tol).y[1] - 1 / 26) for tol in tols]
    @test 0.8 <= fit_order(tols, errs) <= 1.25
end

@testset "adaptive-eccentric-orbit" begin
    # e = 0.8, one period. Error against the exact orbit, in units of tol:
    # calibrated on the reference (deterministic, no seeds): 4810 at
    # tol = 1e-7, 2304 at 1e-10 (the e = 0.5 orbit gives 228 to 443). The
    # bound 2e4 tol is 4x the largest; a controller that ignores the error
    # norm, or a wrong embedded weight, is off by orders of magnitude.
    e = 0.8
    for tol in (1e-7, 1e-10)
        r = solve_adaptive(kepler_rhs!, kepler_initial(e), (0.0, TWO_PI); rtol = tol, atol = tol)
        @test maximum(abs, r.y .- kepler_exact(e, TWO_PI)) <= 2e4 * tol
        # Rejections happen at the looser tolerance (the reference rejects 20
        # steps: the controller overshoots coming into perihelion), and the
        # count is the solver's own: nf = 2 + 6 (accepted + rejected).
        tol == 1e-7 && @test r.nreject > 0
        @test r.nf == 2 + 6 * (r.naccept + r.nreject)
    end
    hs = Float64[]
    tprev = Ref(0.0)
    solve_adaptive(kepler_rhs!, kepler_initial(e), (0.0, TWO_PI); rtol = 1e-8, atol = 1e-8,
                   observe = (t, u) -> (t > 0 && push!(hs, t - tprev[]); tprev[] = t))
    # The step adapts: longest / shortest step (the last, cut to land on the
    # period, excluded) measured 48.6 on the reference; a fixed step gives 1.
    @test maximum(hs) / minimum(hs[1:end-1]) > 10
end

@testset "adaptive-step-limit" begin
    @test_throws ErrorException solve_adaptive(kepler_rhs!, kepler_initial(0.5), (0.0, 100.0);
                                               rtol = 1e-10, atol = 1e-10, maxsteps = 100)
end

@testset "order-fit-least-squares" begin
    # Uneven h and a bend, by hand. x = log h = (0, 1, 3): xm = 4/3,
    # x - xm = (-4/3, -1/3, 5/3), sum((x - xm)^2) = 42/9 = 14/3.
    # y = (0, 1, 2): y - ym = (-1, 0, 1), sum((x - xm)(y - ym)) = 3, slope 9/14.
    # y = (0, 2, 2): y - ym = (-4/3, 2/3, 2/3), sum = 8/3, slope 4/7.
    # (The endpoints alone give 2/3 both times.) ~20 flops: 64 eps.
    h = exp.([0.0, 1.0, 3.0])
    @test isapprox(fit_order(h, exp.([0.0, 1.0, 2.0])), 9 / 14; rtol = 64EPS)
    @test isapprox(fit_order(h, exp.([0.0, 2.0, 2.0])), 4 / 7; rtol = 64EPS)
end
