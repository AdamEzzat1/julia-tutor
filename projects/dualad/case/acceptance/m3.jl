# Hidden acceptance tests, milestone 3: the study (study.jl). Its functions
# are tested on their definitions (recomputed here with the student's own
# package) and on the error model (theory bands); `study()` is tested for
# every claim id the report may quote and for answers that do not depend on
# how the search was written. Every tolerance is derived in a comment.
#
# The case checker includes the student's study/study.jl before this file,
# in the same module.

using Test
using DualAD

const CLAIM_IDS = ["x_lo", "x_hi", "npoints", "target", "rule_step", "cd_err", "cd_err_min", "dual_err", "choice",
                   "poly_err", "trunc_order", "trunc_fit_hmin", "trunc_fit_hmax", "round_slope", "round_fit_hmin",
                   "round_fit_hmax", "cd_best_h", "cd_best_err", "cd_theory_h", "nested_err", "grad_err",
                   "grad_evals_dual", "grad_evals_central", "algo_value_err", "algo_deriv_err", "algo_iters",
                   "robust_x_lo", "robust_x_hi", "robust_cd_err", "robust_dual_err", "robust_choice", "robust_holds",
                   "valid_x_min", "valid_x_max"]

# The ground truth, independent of the student's study: f' of exp(x) sin(x)
# in 256-bit BigFloat (error ~1e-77, far below anything measured here).
truth(x) = setprecision(BigFloat, 256) do
    b = big(x)
    exp(b) * (sin(b) + cos(b))
end
rel(a, x) = Float64(abs(big(a) - truth(x)) / abs(truth(x)))

@testset "error-definition" begin
    # max_error is the largest (and smallest) relative error over the given
    # points, against the exact derivative. Recomputed here with the same
    # calls, so the values agree exactly (isequal); the BigFloat precision
    # cannot change a Float64-rounded relative error at this size.
    xs = [0.55, 0.8, 0.95]
    m, n = max_error(:central, xs)
    errs = [rel(central_diff(x -> exp(x) * sin(x), x, cbrt(eps()) * max(1.0, abs(x))), x) for x in xs]
    @test isapprox(m, maximum(errs); rtol = 1e-6) && isapprox(n, minimum(errs); rtol = 1e-6)
    md, _ = max_error(:dual, xs)
    @test isapprox(md, maximum(rel(derivative(x -> exp(x) * sin(x), x), x) for x in xs); rtol = 1e-6)
end

@testset "error-model-of-central-differences" begin
    # The truncation error at x = 0.7 falls as h^2 (order 2 +- 0.1 over
    # 2^-3 .. 2^-8, measured 1.996) and the rounding error grows as 1/h
    # (slope -1 +- 0.35 over 2^-30 .. 2^-45, measured -1.02; rounding is
    # erratic point to point, so the window is wide).
    ths = [2.0^-k for k in 3:8]
    @test 1.9 <= fit_order(ths, error_curve(0.7, ths)) <= 2.1
    rhs = [2.0^-k for k in 30:45]
    @test -1.35 <= fit_order(rhs, error_curve(0.7, rhs)) <= -0.65
end

@testset "best-uniform-step" begin
    # The best uniform step minimises the largest error over the points;
    # recomputed by brute force on a small grid.
    xs = [0.5, 0.75, 1.0]
    hs = [2.0^-k for k in 14:20]
    h, e = best_uniform_step(xs, hs)
    worst = [maximum(rel(central_diff(x -> exp(x) * sin(x), x, hh), x) for x in xs) for hh in hs]
    @test h in hs
    @test isapprox(e, minimum(worst); rtol = 1e-6)
end

S = study()

@testset "study-returns-every-claim" begin
    @test S isa AbstractDict
    for id in CLAIM_IDS
        @test haskey(S, id)
    end
    @test get(S, "choice", "") in ("dual", "central")
    @test get(S, "robust_choice", "") in ("dual", "central")
    @test get(S, "robust_holds", "") in ("holds", "fails")
end

@testset "operating-point" begin
    # The question fixes these constants: exact identity (isequal).
    @test isequal(get(S, "x_lo", NaN), 0.5) && isequal(get(S, "x_hi", NaN), 1.0)
    @test get(S, "npoints", 0) == 101
    @test isequal(get(S, "target", NaN), 1e-12)
    @test isequal(get(S, "rule_step", NaN), cbrt(eps()) * 1.0)
end

@testset "the-answer" begin
    # The QoI, recomputed independently on the question's 101 points with
    # the rule-of-thumb step (exact recomputation up to the BigFloat
    # rounding of a relative error: 1e-6 relative).
    xs = collect(range(0.5, 1.0; length = 101))
    cd = maximum(rel(central_diff(x -> exp(x) * sin(x), x, cbrt(eps()) * max(1.0, abs(x))), x) for x in xs)
    du = maximum(rel(derivative(x -> exp(x) * sin(x), x), x) for x in xs)
    @test isapprox(S["cd_err"], cd; rtol = 1e-6)
    @test isapprox(S["dual_err"], du; rtol = 1e-6)
    @test S["cd_err_min"] <= S["cd_err"]
    # Theory: the central difference's error at its balanced step is
    # ~eps^(2/3) = 3.7e-11 times O(1) constants (measured 1.7e-11), the
    # dual's a few eps (measured 2.2e-16; bound 8 eps = 1.8e-15).
    @test 1e-12 < S["cd_err"] < 1e-9
    @test S["dual_err"] <= 8 * eps()
    @test S["choice"] == "dual"
    @test S["choice"] == (S["cd_err"] <= S["target"] ? "central" : "dual")
end

@testset "verification-numbers" begin
    # Exact polynomial: 0. Orders in their theory bands (see above). The
    # best uniform step is within a factor 4 of the model's optimum (the
    # model ignores which rounding errors cancel; measured ratio 2.2); its
    # error is no larger than the rule step's error, up to the grid
    # (the rule step is not on the grid: allow 2x).
    @test iszero(S["poly_err"])
    @test 1.9 <= S["trunc_order"] <= 2.1 && S["trunc_fit_hmin"] < S["trunc_fit_hmax"]
    @test -1.35 <= S["round_slope"] <= -0.65 && S["round_fit_hmin"] < S["round_fit_hmax"]
    @test S["round_fit_hmax"] < S["trunc_fit_hmin"]           # the two ranges do not overlap
    @test 0.25 <= S["cd_best_h"] / S["cd_theory_h"] <= 4
    @test S["cd_best_err"] <= 2 * S["cd_err"]
    @test 0 <= S["nested_err"] <= 8 * eps()
    @test 0 <= S["grad_err"] <= 8 * eps()
    @test S["grad_evals_dual"] == 5 && S["grad_evals_central"] == 10
end

@testset "validation-the-algorithm" begin
    # Babylonian sqrt(2) from 1: after 3 steps the value is off by 1.5e-6
    # and the derivative by 3.5e-5 (the derivative converges more slowly in
    # relative terms); both reach rounding level after 5 steps (measured).
    @test 1e-7 < S["algo_value_err"] < 1e-5
    @test S["algo_deriv_err"] > S["algo_value_err"]
    @test S["algo_iters"] == 5
end

@testset "robustness-far-from-the-origin" begin
    # The same interval moved by 96 pi: the function has the same shape, but
    # the rule step cbrt(eps) |x| is 300 times too large, so truncation
    # dominates (measured 3.3e-7). Dual numbers do not care (2.2e-16).
    @test isapprox(S["robust_x_lo"], 0.5 + 96pi; rtol = 4eps()) && isapprox(S["robust_x_hi"], 1.0 + 96pi; rtol = 4eps())
    @test S["robust_cd_err"] > 1e3 * S["cd_err"]
    @test S["robust_dual_err"] <= 8 * eps()
    @test S["robust_choice"] == "dual"
    @test S["robust_holds"] == (S["robust_choice"] == S["choice"] ? "holds" : "fails")
    @test S["valid_x_min"] <= S["x_lo"] && S["valid_x_max"] >= S["robust_x_hi"]
end
