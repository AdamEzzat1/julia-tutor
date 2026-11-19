# Hidden acceptance tests, milestone 3: the study (study.jl). Its functions
# are tested on their definitions (recomputed here with the student's own
# integrators) and on theory; `study()` is tested for every claim id the
# report may quote and for answers that do not depend on how the search
# was written. Every tolerance is derived in a comment.
#
# The case checker includes the student's study/study.jl before this file,
# in the same module.

using Test
using StiffKin

const CLAIM_IDS = ["t_final", "target", "y1_ref", "y2_ref", "y3_ref", "ref_diff", "lambda_40", "bs_rtol", "bs_err",
                   "bs_cost", "bs_steps", "ro_rtol", "ro_err", "ro_cost", "ro_steps", "choice", "cost_ratio",
                   "bs_steps_loose", "bs_order", "ro_order", "order_h_min", "order_h_max", "stab_boundary",
                   "stab_hlam", "mass_err", "naive_bs_t", "naive_bs_ymin", "naive_ro_err", "robust_factor",
                   "robust_lambda", "robust_bs_cost", "robust_ro_cost", "robust_choice", "robust_holds",
                   "valid_t_max", "valid_target"]

# The published value at t = 40 (IVP test-set literature).
const YLIT = [0.7158270687193941, 9.185534764557338e-6, 0.2841637457458413]

bsrun(p, T, rt, at) = integrate((u, h) -> bs32_step(v -> rhs(v, p), u, h), [1.0, 0.0, 0.0], T;
                                rtol = rt, atol = at, h0 = 1e-6, order = 3)
rorun(p, T, rt, at) = integrate((u, h) -> ros2_step(v -> rhs(v, p), v -> jacobian(v, p), u, h), [1.0, 0.0, 0.0], T;
                                rtol = rt, atol = at, h0 = 1e-6, order = 2)
worst(y, r) = maximum(abs.(y .- r) ./ abs.(r))

@testset "helpers-on-their-definitions" begin
    # The cost counts a Jacobian as 3 right-hand sides.
    @test cost(Stats(10, 2, 30, 4, 0.0, 1.0)) == 42
    # The stiff eigenvalue is a root of det(J - lambda I) (the characteristic
    # polynomial at the root, relative to |lambda|^3: 1e-10, a cancellation
    # of terms of size |lambda|^3 ~ 4e10 in rounding).
    y = YLIT
    J = jacobian(y, ROBERTSON)
    l = stiff_eigenvalue(y, ROBERTSON)
    M = J - l * [1.0 0 0; 0 1 0; 0 0 1]
    d = M[1, 1] * (M[2, 2] * M[3, 3] - M[2, 3] * M[3, 2]) - M[1, 2] * (M[2, 1] * M[3, 3] - M[2, 3] * M[3, 1]) +
        M[1, 3] * (M[2, 1] * M[3, 2] - M[2, 2] * M[3, 1])
    @test abs(d) <= 1e-10 * abs(l)^3 && l < -1000
    # BS3's stability function is -1 at the boundary (1e-12: bisection to
    # 1e-15 and a slope of about 2 there).
    b = stability_boundary()
    @test isapprox(abs(1 + b + b^2 / 2 + b^3 / 6), 1; atol = 1e-12) && 2.5 < abs(b) < 2.53
end

S = study()

@testset "study-returns-every-claim" begin
    @test S isa AbstractDict
    for id in CLAIM_IDS
        @test haskey(S, id)
    end
    for k in ("choice", "robust_choice")
        @test get(S, k, "") in ("bs", "ros2")
    end
    @test get(S, "robust_holds", "") in ("holds", "fails")
end

@testset "operating-point-and-reference" begin
    @test isequal(get(S, "t_final", NaN), 40.0) && isequal(get(S, "target", NaN), 1e-4)
    # The reference is far below the budget: within 1e-8 of the published
    # value (measured 1e-10 for y2) and of the second method (measured 7e-11).
    @test worst([S["y1_ref"], S["y2_ref"], S["y3_ref"]], YLIT) <= 1e-8
    @test 0 <= S["ref_diff"] <= 1e-8
    @test -4000 < S["lambda_40"] < -3000
end

@testset "budget-met-and-cheapest" begin
    # Each method's reported tolerance meets the budget, recomputed with the
    # student's own integrator (atol = rtol * 1e-6); the costs are nf + 3 nj.
    y, s = bsrun(ROBERTSON, 40.0, S["bs_rtol"], S["bs_rtol"] * 1e-6)
    @test worst(y, YLIT) <= 1e-4 && S["bs_cost"] == s.nf + 3s.nj && S["bs_steps"] == s.steps
    y, s = rorun(ROBERTSON, 40.0, S["ro_rtol"], S["ro_rtol"] * 1e-6)
    @test worst(y, YLIT) <= 1e-4 && S["ro_cost"] == s.nf + 3s.nj && S["ro_steps"] == s.steps
    # The next looser tolerance on the ladder fails (reference: BS3 at 1e-4
    # misses with 1.3e-4; ROS2 at 3.2e-4 with 2.6e-4).
    for (go, rt) in ((bsrun, S["bs_rtol"]), (rorun, S["ro_rtol"]))
        loose = rt * sqrt(10)
        loose <= 0.1 * (1 + 1e-12) || continue
        y, _ = go(ROBERTSON, 40.0, loose, loose * 1e-6)
        @test worst(y, YLIT) > 1e-4
    end
end

@testset "the-answer" begin
    # Reference: ROS2 3465, BS3 182116, ratio 52.6. Tolerances one ladder
    # rung apart move ROS2's cost by about 1.7x and BS3's by under 1%:
    # window [20, 150].
    @test S["choice"] == "ros2"
    @test 20 <= S["cost_ratio"] <= 150
    @test isapprox(S["cost_ratio"], S["bs_cost"] / S["ro_cost"]; rtol = 4eps())
    # The explicit step count is set by stability: a 300x looser tolerance
    # saves under 5% of the steps (reference 0.06%).
    @test S["bs_steps_loose"] >= 0.95 * S["bs_steps"]
end

@testset "verification-numbers" begin
    # Orders 3 and 2 within 0.1 (fixed steps on a smooth, non-stiff
    # problem); the explicit step within 2% of the stability boundary (the
    # controller sits at the limit; |lambda| varies by 10% over [20, 40]);
    # the linear invariant kept to rounding (1e-12 over 45000 steps).
    @test 2.9 <= S["bs_order"] <= 3.1 && 1.9 <= S["ro_order"] <= 2.1
    @test S["order_h_min"] < S["order_h_max"]
    @test isapprox(S["stab_boundary"], 2.5127453266; rtol = 1e-9)
    @test isapprox(S["stab_hlam"], S["stab_boundary"]; rtol = 0.02)
    @test 0 <= S["mass_err"] <= 1e-12
end

@testset "validation-negative-concentrations" begin
    # With atol = rtol = 1e-4 the explicit run accepts a blow-up: negative
    # concentrations, and it stops long before t = 40 (reference: at 0.042,
    # ymin -3.6e6). ROS2 stays bounded but misses the budget (5.4e-4).
    @test S["naive_bs_t"] < 1 && S["naive_bs_ymin"] < -1
    @test 1e-4 < S["naive_ro_err"] < 1e-2
end

@testset "robustness-slower-reaction" begin
    # k2 and k3 1000 times smaller: the problem is barely stiff (|lambda|
    # about 37), and the explicit method is cheaper (reference 3248 against
    # 7690): the conclusion fails, and the report has to say so.
    @test isequal(S["robust_factor"], 1000.0)
    @test -100 < S["robust_lambda"] < -10
    @test S["robust_choice"] == (S["robust_bs_cost"] < S["robust_ro_cost"] ? "bs" : "ros2")
    @test S["robust_choice"] == "bs"
    @test S["robust_holds"] == (S["robust_choice"] == S["choice"] ? "holds" : "fails")
    @test isequal(S["valid_t_max"], 40.0) && isequal(S["valid_target"], S["target"])
end
