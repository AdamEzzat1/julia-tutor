# The robertson case study (milestone 3). Write the functions below; their
# docstrings are the specification the hidden acceptance tests check.
#
# `tutor case check <dir> 3` loads this file into a module where your
# package is `StiffKin`, runs the acceptance tests, and calls `study()`
# twice in fresh processes. Every value `study()` returns can be quoted in
# report.qmd with a `{claim:<id>}` tag; the checker compares the two.
# Nothing here may be random or read a clock (a clean re-run must give the
# same bits).

using StiffKin

# The question's operating point. Do not change these: the acceptance tests
# check that study() reports them.
const T_END = 40.0                          # the time the concentrations are needed at
const TARGET = 1e-4                         # required relative error of every concentration
const Y0 = [1.0, 0.0, 0.0]                  # all A at t = 0
const RTOLS = [10.0^(-k / 2) for k in 2:20] # the tolerances to try: 1e-1, 3.2e-2, ..., 1e-10
const ATOL_RATIO = 1e-6                     # atol = rtol * ATOL_RATIO; why not 1?
const SLOW = 1000.0                         # the perturbed assumption: k2 and k3 this many times smaller
const H0 = 1e-6                             # the first step tried

"""The cost of an integration: right-hand sides plus 3 per Jacobian (what a finite-difference Jacobian would cost)."""
cost(s::Stats) = s.nf + 3 * s.nj

"""The two integrators for the rate constants `p`, as `(y, h) -> step` functions."""
function steppers(p::Kinetics)
    f(y) = rhs(y, p)
    jac(y) = jacobian(y, p)
    return (y, h) -> bs32_step(f, y, h), (y, h) -> ros2_step(f, jac, y, h)
end

"""Solve with `method` (:bs or :ros2) at relative tolerance `rtol`, with atol = rtol * ATOL_RATIO."""
function solve(method::Symbol, p::Kinetics, T, rtol; y0 = Y0, atol = rtol * ATOL_RATIO)
    bs, ro = steppers(p)
    method === :bs && return integrate(bs, y0, T; rtol = rtol, atol = atol, h0 = H0, order = 3)
    method === :ros2 && return integrate(ro, y0, T; rtol = rtol, atol = atol, h0 = H0, order = 2)
    throw(ArgumentError("method must be :bs or :ros2"))
end

"""The largest relative error over the components."""
relerr(y, ref) = maximum(abs.(y .- ref) ./ abs.(ref))

"""
    reference(p, T) -> (y, diff)

The ground truth at T: BS3(2) at rtol 1e-10 (atol 1e-16), and the largest
relative difference of ROS2 at the same tolerance from it, which bounds
the reference's own error when both are far below TARGET.
"""
function reference(p::Kinetics, T)
    error("TODO: reference")
end

"""
    cheapest(method, p, T, ref) -> (rtol, err, cost, stats)

The first tolerance in RTOLS (loosest first) at which `method` meets
TARGET in every component against `ref`, with its error, cost and stats.
"""
function cheapest(method::Symbol, p::Kinetics, T, ref)
    error("TODO: cheapest")
end

"""
    stiff_eigenvalue(y, p) -> Float64

The most negative eigenvalue of the Jacobian at `y`. One eigenvalue is 0
(why?); the other two are the roots of lambda^2 - tr(J) lambda + m, where m
is the sum of the principal 2x2 minors. Both are real and negative along
Robertson's solution.
"""
function stiff_eigenvalue(y, p::Kinetics)
    error("TODO: stiff_eigenvalue")
end

"""
    stability_boundary() -> Float64

Where BS3's stability function R(z) = 1 + z + z^2/2 + z^3/6 equals -1 on
the negative real axis (bisection on [-3, -2] to 1e-15).
"""
function stability_boundary()
    error("TODO: stability_boundary")
end

"""`n` fixed steps of length T / n with `step` from `y0` (no error control); the final y."""
function fixed_run(step, y0, T, n)
    error("TODO: fixed_run")
end

"""
    study() -> Dict{String,Any}

Every number your report quotes, by claim id (`tutor case show robertson`
lists them with what each one is). The ids:

    t_final target y1_ref y2_ref y3_ref ref_diff lambda_40
    bs_rtol bs_err bs_cost bs_steps ro_rtol ro_err ro_cost ro_steps choice cost_ratio bs_steps_loose
    bs_order ro_order order_h_min order_h_max stab_boundary stab_hlam mass_err
    naive_bs_t naive_bs_ymin naive_ro_err
    robust_factor robust_lambda robust_bs_cost robust_ro_cost robust_choice robust_holds
    valid_t_max valid_target

`choice` and `robust_choice` are "bs" or "ros2"; `robust_holds` is "holds"
or "fails". `cost_ratio` is BS3(2)'s cost over ROS2's. `bs_steps_loose`:
BS3(2)'s steps at rtol 1e-2. The orders: fixed steps on the rotation
y1' = y2, y2' = -y1 to t = 1 against its exact solution, with steps you
choose. `stab_boundary` is the magnitude of stability_boundary();
`stab_hlam` is BS3(2)'s mean accepted step from t = 20 to 40 (at its
budget tolerance, starting from the reference state at 20) times
|lambda| at t = 30. `mass_err`: the largest |y1 + y2 + y3 - 1| of the two
chosen runs. The naive runs use atol = rtol = 1e-4: how far BS3(2) gets
(stats.t), the smallest concentration it accepted, and ROS2's error.
The robust claims repeat the choice with k2 and k3 divided by SLOW.
"""
function study()
    out = Dict{String,Any}()
    out["t_final"], out["target"] = T_END, TARGET
    error("TODO: study")
    return out
end
