# The robertson case study (milestone 3), reference version.
#
# Loaded by the case checker into a module where your package is
# `StiffKin`. Every value `study()` returns can be quoted in report.qmd with
# a `{claim:<id>}` tag; the checker re-runs this file in a fresh process
# twice and compares. Nothing here may be random or read a clock.

using StiffKin

# ---- the operating point of the question ------------------------------------------------------

const T_END = 40.0                          # the time the concentrations are needed at
const TARGET = 1e-4                         # required relative error of every concentration
const Y0 = [1.0, 0.0, 0.0]                  # all A at t = 0
const RTOLS = [10.0^(-k / 2) for k in 2:20] # the tolerances tried: 1e-1, 3.2e-2, ..., 1e-10
const ATOL_RATIO = 1e-6                     # atol = rtol * 1e-6, far below B's scale (1e-5)
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

The ground truth at T: BS3(2) at rtol 1e-10 (atol 1e-16), and how far
ROS2 at the same tolerance is from it (the largest relative difference),
which bounds the reference's own error when both are far below TARGET.
"""
function reference(p::Kinetics, T)
    yb, _ = solve(:bs, p, T, 1e-10; atol = 1e-16)
    yr, _ = solve(:ros2, p, T, 1e-10; atol = 1e-16)
    return yb, relerr(yr, yb)
end

"""
    cheapest(method, p, T, ref) -> (rtol, err, cost, stats)

The first tolerance in RTOLS (loosest first) at which `method` meets
TARGET in every component against `ref`, with its error, cost and stats.
"""
function cheapest(method::Symbol, p::Kinetics, T, ref)
    for rt in RTOLS
        y, s = solve(method, p, T, rt)
        e = relerr(y, ref)
        e <= TARGET && return (rt, e, cost(s), s)
    end
    error("no tolerance in RTOLS meets the budget for $method")
end

"""
    stiff_eigenvalue(y, p) -> Float64

The most negative eigenvalue of the Jacobian at `y`. One eigenvalue is 0
(mass conservation: the columns sum to 0); the other two are the roots of
lambda^2 - tr(J) lambda + m, m the sum of the principal 2x2 minors. Both are
real and negative along Robertson's solution.
"""
function stiff_eigenvalue(y, p::Kinetics)
    J = jacobian(y, p)
    tr = J[1, 1] + J[2, 2] + J[3, 3]
    m = (J[1, 1] * J[2, 2] - J[1, 2] * J[2, 1]) + (J[1, 1] * J[3, 3] - J[1, 3] * J[3, 1]) +
        (J[2, 2] * J[3, 3] - J[2, 3] * J[3, 2])
    return (tr - sqrt(tr^2 - 4m)) / 2
end

"""
    stability_boundary() -> Float64

Where BS3's stability function R(z) = 1 + z + z^2/2 + z^3/6 crosses -1 on
the negative real axis (bisection on [-3, -2] to 1e-15): an explicit step
on a mode lambda is stable only if h |lambda| is at most its magnitude.
"""
function stability_boundary()
    R(z) = 1 + z + z^2 / 2 + z^3 / 6
    lo, hi = -3.0, -2.0
    while hi - lo > 1e-15
        m = (lo + hi) / 2
        abs(R(m)) > 1 ? (lo = m) : (hi = m)
    end
    return (lo + hi) / 2
end

"""`n` fixed steps of length T / n with `step` from `y0` (no error control)."""
function fixed_run(step, y0, T, n)
    y = Vector{Float64}(y0)
    h = T / n
    for _ in 1:n
        y = step(y, h)[1]
    end
    return y
end

function study()
    out = Dict{String,Any}()
    p = ROBERTSON
    out["t_final"], out["target"] = T_END, TARGET

    # ---- the ground truth ----------------------------------------------------------------------
    ref, rdiff = reference(p, T_END)
    out["y1_ref"], out["y2_ref"], out["y3_ref"] = ref[1], ref[2], ref[3]
    out["ref_diff"] = rdiff
    out["lambda_40"] = stiff_eigenvalue(ref, p)

    # ---- the question: the cheapest tolerance meeting the budget, per method --------------------------
    brt, berr, bcost, bs = cheapest(:bs, p, T_END, ref)
    rrt, rerr, rcost, rs = cheapest(:ros2, p, T_END, ref)
    out["bs_rtol"], out["bs_err"], out["bs_cost"], out["bs_steps"] = brt, berr, bcost, bs.steps
    out["ro_rtol"], out["ro_err"], out["ro_cost"], out["ro_steps"] = rrt, rerr, rcost, rs.steps
    out["choice"] = bcost < rcost ? "bs" : "ros2"
    out["cost_ratio"] = bcost / rcost
    # The explicit method's steps barely depend on the tolerance: stability sets them.
    out["bs_steps_loose"] = solve(:bs, p, T_END, 1e-2)[2].steps

    # ---- verification ---------------------------------------------------------------------------
    # Orders with fixed steps on a non-stiff rotation y1' = y2, y2' = -y1 to
    # t = 1, against the exact solution: 3 for BS3, 2 for ROS2.
    rot(y) = [y[2], -y[1]]
    jrot(y) = [0.0 1.0; -1.0 0.0]
    ns = [20, 40, 80, 160]
    ex = [cos(1.0), -sin(1.0)]
    eb = [maximum(abs, fixed_run((y, h) -> bs32_step(rot, y, h), [1.0, 0.0], 1.0, n) .- ex) for n in ns]
    er = [maximum(abs, fixed_run((y, h) -> ros2_step(rot, jrot, y, h), [1.0, 0.0], 1.0, n) .- ex) for n in ns]
    out["bs_order"] = fit_order(1 ./ ns, eb)
    out["ro_order"] = fit_order(1 ./ ns, er)
    out["order_h_min"], out["order_h_max"] = 1 / 160, 1 / 20
    # The explicit step is pinned to the stability limit: the mean step from
    # t = 20 to 40 times |lambda| at t = 30, against the boundary of R(z).
    y20, _ = solve(:bs, p, 20.0, 1e-10; atol = 1e-16)
    y30, _ = solve(:bs, p, 30.0, 1e-10; atol = 1e-16)
    _, s2040 = solve(:bs, p, 20.0, brt; y0 = y20)
    out["stab_boundary"] = abs(stability_boundary())
    out["stab_hlam"] = (20.0 / s2040.steps) * abs(stiff_eigenvalue(y30, p))
    # Mass: both methods keep the linear invariant y1 + y2 + y3 = 1.
    yb, _ = solve(:bs, p, T_END, brt)
    yr, _ = solve(:ros2, p, T_END, rrt)
    out["mass_err"] = max(abs(sum(yb) - 1), abs(sum(yr) - 1))

    # ---- validation: concentrations are not negative ------------------------------------------------
    # A common default, atol = rtol = 1e-4, is above B's scale (1e-5): B's
    # error, and the instability of the explicit method in B's fast mode,
    # are invisible to the controller.
    _, nb = solve(:bs, p, T_END, 1e-4; atol = 1e-4)
    out["naive_bs_t"] = nb.t
    out["naive_bs_ymin"] = nb.ymin
    ynr, _ = solve(:ros2, p, T_END, 1e-4; atol = 1e-4)
    out["naive_ro_err"] = relerr(ynr, ref)

    # ---- uncertainty: a slower reaction (not stiff) -----------------------------------------------------
    q = Kinetics(p.k1, p.k2 / SLOW, p.k3 / SLOW)
    qref, _ = reference(q, T_END)
    _, _, qb, _ = cheapest(:bs, q, T_END, qref)
    _, _, qr, _ = cheapest(:ros2, q, T_END, qref)
    out["robust_factor"] = SLOW
    out["robust_lambda"] = stiff_eigenvalue(qref, q)
    out["robust_bs_cost"], out["robust_ro_cost"] = qb, qr
    out["robust_choice"] = qb < qr ? "bs" : "ros2"
    out["robust_holds"] = out["robust_choice"] == out["choice"] ? "holds" : "fails"

    # ---- where the conclusion was tested --------------------------------------------------------------
    out["valid_t_max"] = T_END
    out["valid_target"] = TARGET
    return out
end
