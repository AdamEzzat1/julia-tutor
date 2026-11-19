# Hidden acceptance tests, milestone 3: the study (study.jl). Its functions
# are tested on their definitions (recomputed here with the student's own
# solver) and on theory; `study()` is tested for every claim id the report
# may quote and for answers that do not depend on how the search was
# written. Every tolerance is derived in a comment.
#
# The case checker includes the student's study/study.jl before this file,
# in the same module.

using Test
using Heat1D

const CLAIM_IDS = ["kappa", "t_final", "target", "exact_mid", "n_space", "space_err", "ns_ftcs", "cost_ftcs",
                   "time_err_ftcs", "ns_be", "cost_be", "ns_cn", "cost_cn", "time_err_cn", "choice", "cost_ratio",
                   "cancel_n", "cancel_ns", "cancel_total_err", "cancel_space_err", "mms_space_order", "mms_dx_min",
                   "mms_dx_max", "mms_time_order_cn", "mms_time_order_be", "mms_dt_min", "mms_dt_max", "quad_err",
                   "cfl_measured", "cfl_theory", "cn_peaks", "be_peaks", "cn_peak_excess", "robust_n_space",
                   "robust_ns_cn", "robust_cost_cn", "robust_cost_ftcs", "robust_cost_be", "robust_choice",
                   "robust_cost_ratio", "robust_holds", "valid_n_max", "valid_target"]

const T_ = 0.01
mid(ic, N, ns, m) = solve_heat(ic === :smooth ? HeatProblem(1.0, x -> sinpi(x)) :
                               HeatProblem(1.0, x -> (0.25 < x < 0.75) ? 1.0 : (x == 0.25 || x == 0.75) ? 0.5 : 0.0),
                               N, ns, T_; method = m)[2][(N + 1) ÷ 2]

@testset "exact-midpoint-values" begin
    # The smooth profile's exact value is exp(-pi^2 T); the top hat's, its
    # Fourier series (terms below 1e-17 from k = 20 on). Both to 1e-14
    # relative (a sum of 40 terms).
    @test isapprox(exact_mid(:smooth), exp(-pi^2 * T_); rtol = 1e-14)
    s = sum(2 * (cospi(k / 4) - cospi(3k / 4)) / (k * pi) * exp(-k^2 * pi^2 * T_) * sinpi(k / 2) for k in 1:60)
    @test isapprox(exact_mid(:tophat), s; rtol = 1e-14)
end

@testset "error-split-definitions" begin
    # space_error: CN with many steps against the exact value; time_error:
    # the method against the fine run on the same grid. Recomputed here
    # (the fine run's own time error, ~1e-10, is far below what this
    # compares: 1e-3 relative agreement).
    se = space_error(:smooth, 63)
    @test isapprox(se, abs(mid(:smooth, 63, 2^14, :cn) - exp(-pi^2 * T_)) / exp(-pi^2 * T_); rtol = 1e-3)
    te = time_error(:smooth, 63, 4, :be)
    @test isapprox(te, abs(mid(:smooth, 63, 4, :be) - mid(:smooth, 63, 2^14, :cn)) / exp(-pi^2 * T_); rtol = 1e-3)
end

@testset "stability-limit-measured" begin
    # Bisection on the growth of the fastest mode agrees with von Neumann's
    # limit to the bisection's resolution and the finite run (1e-5).
    @test isapprox(stability_limit(15), 1 / (2 * sinpi(15 / 32)^2); atol = 1e-5)
end

S = study()

@testset "study-returns-every-claim" begin
    @test S isa AbstractDict
    for id in CLAIM_IDS
        @test haskey(S, id)
    end
    for k in ("choice", "robust_choice")
        @test get(S, k, "") in ("ftcs", "be", "cn")
    end
    @test get(S, "robust_holds", "") in ("holds", "fails")
end

@testset "operating-point" begin
    @test isequal(get(S, "kappa", NaN), 1.0) && isequal(get(S, "t_final", NaN), 0.01)
    @test isequal(get(S, "target", NaN), 1e-5)
    @test isapprox(get(S, "exact_mid", NaN), exp(-pi^2 * 0.01); rtol = 1e-14)
end

@testset "budget-split-and-met" begin
    # Each half of the budget is met, recomputed with the student's own
    # solver at the reported settings (1e-3 relative, as above), and the
    # costs are grid-point updates.
    tgt = S["target"]
    for (m, ns, c) in ((:ftcs, S["ns_ftcs"], S["cost_ftcs"]), (:be, S["ns_be"], S["cost_be"]), (:cn, S["ns_cn"], S["cost_cn"]))
        N = S["n_space"]
        @test abs(mid(:smooth, N, ns, m) - mid(:smooth, N, 2^14, :cn)) / S["exact_mid"] <= tgt / 2 * (1 + 1e-3)
        @test c == N * ns
    end
    @test S["space_err"] <= tgt / 2 && S["time_err_cn"] <= tgt / 2 && S["time_err_ftcs"] <= tgt / 2
    # FTCS is at or below its stability limit r = 1/2.
    @test S["t_final"] / S["ns_ftcs"] <= 0.5 / (S["n_space"] + 1)^2 * (1 + 1e-12)
end

@testset "settings-near-the-cheapest" begin
    # The grid is the coarsest power-of-2 grid meeting the space half: the
    # next coarser one fails it (reference: N = 127 gives 4.95e-6, N = 63
    # gives 2.0e-5). CN's step count: half as many steps fails the time half.
    N = S["n_space"]
    Nc = (N + 1) ÷ 2 - 1
    @test abs(mid(:smooth, Nc, 2^14, :cn) - S["exact_mid"]) / S["exact_mid"] > S["target"] / 2
    if S["ns_cn"] >= 2
        @test abs(mid(:smooth, N, S["ns_cn"] ÷ 2, :cn) - mid(:smooth, N, 2^14, :cn)) / S["exact_mid"] > S["target"] / 2
    end
end

@testset "the-answer" begin
    # Reference: CN 1016 updates, FTCS 166624, BE 130048: ratio 164. With
    # settings within a factor 2 of the cheapest in each direction, the
    # ratio stays within [164 / 4, 164 * 4]: window [30, 700].
    @test S["choice"] == "cn"
    @test 30 <= S["cost_ratio"] <= 700
    @test isapprox(S["cost_ratio"], S["cost_ftcs"] / S["cost_cn"]; rtol = 4eps())
end

@testset "cancellation-shown" begin
    # On a grid too coarse for the space budget, some step count's total
    # error is far below the space error it contains (measured 100x).
    @test S["cancel_space_err"] > S["target"] / 2
    @test S["cancel_total_err"] < S["cancel_space_err"] / 10
    @test isapprox(S["cancel_total_err"], abs(mid(:smooth, S["cancel_n"], S["cancel_ns"], :cn) - S["exact_mid"]) / S["exact_mid"]; rtol = 1e-6)
end

@testset "verification-numbers" begin
    # Theory: order 2 in space and in time for CN, 1 for BE (+- 0.1); the
    # quadratic to rounding (50 steps of 16-eps solves); the stability
    # limit to 1e-5.
    @test 1.9 <= S["mms_space_order"] <= 2.1 && S["mms_dx_min"] < S["mms_dx_max"]
    @test 1.9 <= S["mms_time_order_cn"] <= 2.1 && 0.9 <= S["mms_time_order_be"] <= 1.1
    @test S["mms_dt_min"] < S["mms_dt_max"]
    @test 0 <= S["quad_err"] <= 50 * 16 * eps()
    @test isapprox(S["cfl_measured"], S["cfl_theory"]; atol = 1e-5)
    @test isapprox(S["cfl_theory"], 1 / (2 * sinpi(31 / 64)^2); rtol = 1e-12)
end

@testset "validation-one-peak" begin
    # Physics: one peak. CN with one long step on the top hat has more
    # (reference 3, its maximum 0.029 above the midpoint); BE has one.
    @test S["be_peaks"] == 1
    @test S["cn_peaks"] > 1
    @test S["cn_peak_excess"] > 1e-3
end

@testset "robustness-rough-profile" begin
    # The top hat needs a finer grid (reference N = 1023) and more CN steps
    # (128); CN stays the cheapest (reference ratio 164).
    @test S["robust_n_space"] > S["n_space"]
    @test S["robust_ns_cn"] > S["ns_cn"]
    @test S["robust_choice"] == "cn"
    @test S["robust_holds"] == (S["robust_choice"] == S["choice"] ? "holds" : "fails")
    @test isapprox(S["robust_cost_ratio"], S["robust_cost_ftcs"] / S["robust_cost_cn"]; rtol = 4eps())
    @test S["valid_n_max"] >= S["robust_n_space"] && isequal(S["valid_target"], S["target"])
end
