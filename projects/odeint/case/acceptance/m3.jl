# Hidden acceptance tests, milestone 3: the study (study.jl). Its functions
# are tested on their definitions (recomputed here with the student's own
# solvers) and on the physics (theory bands); `study()` is tested for every
# claim id the report may quote and for answers that do not depend on how
# the search was written. Every tolerance is derived in a comment.
#
# The case checker includes the student's study/study.jl before this file,
# in the same module.

using Test
using ODEInt

const TWO_PI_ = 2 * pi
const CLAIM_IDS = ["eccentricity", "norbits", "target", "tol_dp54", "err_dp54", "nf_dp54", "nper_verlet",
                   "err_verlet", "nf_verlet", "choice", "cost_ratio", "cost_ratio_lo", "cost_ratio_hi",
                   "conv_order", "conv_fit_hmin", "conv_fit_hmax", "verlet_order", "verlet_fit_hmin",
                   "verlet_fit_hmax", "tol_slope", "exact_linear_err", "pos_err_dp54", "pos_err_verlet",
                   "drift_exp_dp54", "drift_exp_verlet", "drift_fit_kmin", "drift_fit_kmax", "robust_e",
                   "robust_cost_ratio", "robust_choice", "robust_holds", "valid_e_min", "valid_e_max",
                   "valid_norbits_max"]

relE(u, E0) = abs(kepler_energy(u) - E0) / abs(E0)

@testset "energy-error-definition" begin
    # max_energy_error is the largest relative energy error over every step,
    # with the solver's own evaluation count. Recomputed here with the same
    # solver calls, so the values agree to rounding of the max (exact in
    # practice; 1e-12 relative allows a different but equivalent order of
    # operations in the energy).
    e, k = 0.5, 3
    u0 = kepler_initial(e)
    E0 = kepler_energy(u0)
    m = Ref(0.0)
    r = solve_adaptive(kepler_rhs!, u0, (0.0, k * TWO_PI_); rtol = 1e-8, atol = 1e-8,
                       observe = (t, u) -> (m[] = max(m[], relE(u, E0))))
    err, nf = max_energy_error(:dp54, e, k, 1e-8)
    @test isapprox(err, m[]; rtol = 1e-12)
    @test nf == r.nf
    mv = Ref(0.0)
    _, _, nfv = solve_verlet(kepler_accel!, u0[1:2], u0[3:4], (0.0, k * TWO_PI_), 500k;
                             observe = (t, q, p) -> (mv[] = max(mv[], relE([q; p], E0))))
    errv, nfv2 = max_energy_error(:verlet, e, k, 500)
    @test isapprox(errv, mv[]; rtol = 1e-12)
    @test nfv2 == nfv == 1 + 500k
end

@testset "verlet-energy-law" begin
    # O(h^2) and bounded: halving h divides the max by 4 (+ O(h^2): window
    # 4 +- 0.2, measured 4.0013); 10x the horizon leaves it unchanged
    # (measured ratio 1 + 1.3e-9; window 1 +- 0.01).
    @test 3.8 <= max_energy_error(:verlet, 0.5, 10, 500)[1] / max_energy_error(:verlet, 0.5, 10, 1000)[1] <= 4.2
    @test 0.99 <= max_energy_error(:verlet, 0.5, 100, 500)[1] / max_energy_error(:verlet, 0.5, 10, 500)[1] <= 1.01
end

@testset "dp54-energy-law" begin
    # Linear growth at fixed tolerance: 10x the horizon multiplies the max by
    # ~10 (measured 9.93 for 100 -> 1000 orbits at tol 1e-10; the first
    # orbit's transient lowers it): window [8, 12].
    q = max_energy_error(:dp54, 0.5, 1000, 1e-10)[1] / max_energy_error(:dp54, 0.5, 100, 1e-10)[1]
    @test 8 <= q <= 12
end

@testset "drift-exponents" begin
    # Theory: 1 (linear drift) and 0 (bounded). Measured with the reference
    # over 40 ... 1280 orbits: 0.99 and 3e-7. Windows +- 0.1 distinguish
    # them from each other and from a random walk (0.5).
    @test 0.9 <= drift_exponent(:dp54, 0.5, 1e-9) <= 1.1
    @test -0.1 <= drift_exponent(:verlet, 0.5, 300) <= 0.1
end

S = study()

@testset "study-returns-every-claim" begin
    @test S isa AbstractDict
    for id in CLAIM_IDS
        @test haskey(S, id)
    end
    @test get(S, "choice", "") in ("dp54", "verlet")
    @test get(S, "robust_holds", "") in ("holds", "fails")
end

@testset "operating-point" begin
    # The question fixes these constants: exact identity (isequal), no rounding involved.
    @test isequal(get(S, "eccentricity", NaN), 0.5)
    @test get(S, "norbits", 0) == 1000
    @test isequal(get(S, "target", NaN), 1e-6)
end

@testset "settings-meet-the-budget" begin
    # The chosen settings meet the target, recomputed with the student's own
    # function (exact recomputation: same calls, deterministic).
    e, N, target = 0.5, 1000, 1e-6
    errd, nfd = max_energy_error(:dp54, e, N, S["tol_dp54"])
    @test errd <= target
    @test nfd == S["nf_dp54"]
    errv, nfv = max_energy_error(:verlet, e, N, S["nper_verlet"])
    @test errv <= target
    @test nfv == S["nf_verlet"]
end

@testset "settings-are-near-the-cheapest" begin
    # Cheapest within the stated resolution. DP5(4): the energy error is not
    # monotone in the tolerance (reference: 5.6e-9 gives 9.3e-6, 3.16e-9
    # gives 7.9e-7, 1.78e-9 gives 1.5e-6, 1e-9 gives 1.7e-6, 3.16e-10 gives
    # 9.3e-7), so "a looser neighbour fails" cannot tell the cheapest from a
    # costlier pass. The definition instead: no tolerance on the
    # quarter-decade grid 10^(-j/4) from 1e-6 down to yours meets the
    # budget (a finer grid of your own is fine; it can only find a looser
    # pass, and this checks the grid points above it). Verlet's error is
    # monotone in h: 10% fewer steps fails (10372 pass, 9334 give 1.2e-6).
    e, N, target = 0.5, 1000, 1e-6
    tol = S["tol_dp54"]
    @test max_energy_error(:dp54, e, N, tol)[1] <= target
    for j in 24:64
        g = 10.0^(-j / 4)
        g > tol * (1 + 1e-12) || break
        @test max_energy_error(:dp54, e, N, g)[1] > target
    end
    @test max_energy_error(:verlet, e, N, floor(Int, 0.9 * S["nper_verlet"]))[1] > target
end

@testset "the-answer" begin
    # Measured with the reference: DP5(4) needs 506498 evaluations, Verlet
    # 10372001, ratio 20.5 (grid bounds 20.3 to 23.0). With settings within
    # the resolution above, DP5(4)'s cost is within 10^(0.5/5) = 1.26x of the
    # reference's and Verlet's within 1/0.9 = 1.11x, so the ratio lies in
    # [20.5 / 1.26 / 1.11, 20.5 * 1.26 * 1.11] = [14.6, 28.7]: window [12, 35].
    @test S["choice"] == "dp54"
    @test 12 <= S["cost_ratio"] <= 35
    @test S["cost_ratio_lo"] <= S["cost_ratio"] <= S["cost_ratio_hi"]
    @test isapprox(S["cost_ratio"], S["nf_verlet"] / S["nf_dp54"]; rtol = 4eps())
    @test S["choice"] == (S["nf_dp54"] <= S["nf_verlet"] ? "dp54" : "verlet")
end

@testset "verification-numbers" begin
    # Theory bands (see the visible tests): DP5 order 5 (+- 0.35 for the fit
    # range's pre-asymptotic end), Verlet 2 +- 0.1, tolerance slope 1
    # (0.85 to 1.2), exact solution to rounding (64 * 7 steps * eps * 7.4).
    @test 4.65 <= S["conv_order"] <= 5.35
    @test S["conv_fit_hmin"] < S["conv_fit_hmax"]
    @test 1.9 <= S["verlet_order"] <= 2.1
    @test S["verlet_fit_hmin"] < S["verlet_fit_hmax"]
    @test 0.85 <= S["tol_slope"] <= 1.2
    @test 0 <= S["exact_linear_err"] <= 64 * 7 * eps() * 7.4
end

@testset "drift-and-robustness" begin
    # The drift exponents with their fit range, and the perturbed
    # assumption: at e = 0.6 DP5(4) is still cheaper (reference ratio 19.4).
    @test 0.9 <= S["drift_exp_dp54"] <= 1.1
    @test -0.1 <= S["drift_exp_verlet"] <= 0.1
    @test 1 <= S["drift_fit_kmin"] < S["drift_fit_kmax"] <= S["norbits"] * 2
    @test S["robust_e"] != S["eccentricity"]
    @test S["robust_choice"] == "dp54"
    @test S["robust_holds"] == (S["robust_choice"] == S["choice"] ? "holds" : "fails")
end

@testset "validation-positions" begin
    # Position errors are positive and below the orbit's size (they are
    # 0.006 and 0.016 for the reference; an error near 2 means the planet is
    # on the wrong side of the orbit).
    @test 0 < S["pos_err_dp54"] < 1
    @test 0 < S["pos_err_verlet"] < 1
    @test S["valid_e_min"] <= S["eccentricity"] <= S["valid_e_max"]
    @test S["valid_norbits_max"] == S["norbits"]
end
