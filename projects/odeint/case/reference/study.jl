# The odeint case study (milestone 3), reference version.
#
# Loaded by the case checker into a module where your package is `ODEInt`.
# Every value `study()` returns can be quoted in report.qmd with a
# `{claim:<id>}` tag; the checker re-runs this file in a fresh process twice
# and compares. Nothing here may be random or read a clock.

using ODEInt

const TWO_PI = 2 * pi

# ---- the operating point of the question ------------------------------------------------------

const ECC = 0.5            # eccentricity of the orbit
const NORBITS = 1000       # integration horizon, in orbits
const TARGET = 1e-6        # required max relative energy error over the horizon
const ROBUST_ECC = 0.6     # the perturbed assumption: a more eccentric orbit

"""
    max_energy_error(method, e, norbits, setting) -> (err, nf)

Integrate `norbits` orbits of eccentricity `e` from perihelion with
`method` (`:dp54`, adaptive with `rtol = atol = setting`, or `:verlet`,
fixed step with `setting` steps per orbit). Returns the largest relative
energy error |E(t) - E0| / |E0| seen at any step, and the number of
right-hand-side (force) evaluations.
"""
function max_energy_error(method::Symbol, e, norbits::Integer, setting)
    u0 = kepler_initial(e)
    E0 = kepler_energy(u0)
    m = 0.0
    tf = norbits * TWO_PI
    if method === :dp54
        r = solve_adaptive(kepler_rhs!, u0, (0.0, tf); rtol = setting, atol = setting,
                           observe = (t, u) -> (m = max(m, abs(kepler_energy(u) - E0) / abs(E0))))
        return m, r.nf
    elseif method === :verlet
        _, _, nf = solve_verlet(kepler_accel!, u0[1:2], u0[3:4], (0.0, tf), norbits * setting;
                                observe = (t, q, p) -> (m = max(m, abs(kepler_energy(q, p) - E0) / abs(E0))))
        return m, nf
    end
    throw(ArgumentError("method must be :dp54 or :verlet"))
end

"""
    drift_exponent(method, e, setting; orbits = [40, 80, ..., 1280]) -> Float64

The growth exponent of the energy error: the fitted slope of
log(running maximum of the relative energy error up to orbit k) on log(k),
over `orbits`. 1 means linear growth, 0 bounded. The range starts at 40
orbits: before that the error of the first orbit (a transient) can hide
the drift (measured at tol 3.2e-9: a plateau at 3e-8 up to 20 orbits).
"""
function drift_exponent(method::Symbol, e, setting; orbits = [40 * 2^j for j in 0:5])
    errs = [max_energy_error(method, e, k, setting)[1] for k in orbits]
    return fit_order(Float64.(orbits), errs)
end

"""
    cheapest_setting(method, e, norbits, target) -> (setting, err, nf)

The cheapest setting found that keeps `max_energy_error` at or below
`target`, with its error and cost. `:dp54`: tolerances 1e-6, 10^(-6.25), ...
(quarter decades), the first that passes. (Looser tolerances are not tried:
over 1000 orbits at 1e-4 the energy error is so large that the orbit decays
towards a collision and the step count explodes.) `:verlet`: the steps per
orbit predicted from the O(h^2) law fitted to one short run, then raised by
1% until it passes.
"""
function cheapest_setting(method::Symbol, e, norbits::Integer, target)
    if method === :dp54
        for j in 24:64
            tol = 10.0^(-j / 4)
            err, nf = max_energy_error(:dp54, e, norbits, tol)
            err <= target && return (tol, err, nf)
        end
        error("no tolerance down to 1e-16 meets the target")
    elseif method === :verlet
        err1, _ = max_energy_error(:verlet, e, 1, 200)
        n = ceil(Int, 200 * sqrt(err1 / target))
        while true
            err, nf = max_energy_error(:verlet, e, norbits, n)
            err <= target && return (n, err, nf)
            n = ceil(Int, 1.01 * n)
        end
    end
    throw(ArgumentError("method must be :dp54 or :verlet"))
end

"""The cost of the best setting one step coarser than `cheapest_setting`'s (it fails the target)."""
function failing_neighbour(method::Symbol, e, norbits::Integer, setting)
    coarser = method === :dp54 ? setting * 10^(1 / 4) : floor(Int, setting / 1.01)
    return max_energy_error(method, e, norbits, coarser)
end

"""Position error at the end of the horizon against the exact orbit (validation of the proxy)."""
function position_error(method::Symbol, e, norbits::Integer, setting)
    u0 = kepler_initial(e)
    tf = norbits * TWO_PI
    exact = kepler_exact(e, tf)
    if method === :dp54
        y = solve_adaptive(kepler_rhs!, u0, (0.0, tf); rtol = setting, atol = setting).y
        return hypot(y[1] - exact[1], y[2] - exact[2])
    end
    q, _, _ = solve_verlet(kepler_accel!, u0[1:2], u0[3:4], (0.0, tf), norbits * setting)
    return hypot(q[1] - exact[1], q[2] - exact[2])
end

function study()
    out = Dict{String,Any}()
    out["eccentricity"] = ECC
    out["norbits"] = NORBITS
    out["target"] = TARGET

    # ---- verification ----------------------------------------------------------------------
    # DP5 order: one period, 200 ... 1600 steps (the asymptotic range; below
    # 200 the error is pre-asymptotic, above 1600 it nears rounding).
    u0, uT = kepler_initial(ECC), kepler_exact(ECC, TWO_PI)
    ns = [200, 400, 800, 1600]
    hs = TWO_PI ./ ns
    errs = [maximum(abs, solve_fixed(kepler_rhs!, u0, (0.0, TWO_PI), n)[1] .- uT) for n in ns]
    out["conv_order"] = fit_order(hs, errs)
    out["conv_fit_hmin"], out["conv_fit_hmax"] = minimum(hs), maximum(hs)
    # Verlet order on the same orbit, 400 ... 3200 steps.
    vns = [400, 800, 1600, 3200]
    vhs = TWO_PI ./ vns
    verrs = map(vns) do n
        q, p, _ = solve_verlet(kepler_accel!, u0[1:2], u0[3:4], (0.0, TWO_PI), n)
        maximum(abs, [q; p] .- uT)
    end
    out["verlet_order"] = fit_order(vhs, verrs)
    out["verlet_fit_hmin"], out["verlet_fit_hmax"] = minimum(vhs), maximum(vhs)
    # Tolerance proportionality: one period, tol = 1e-5 ... 1e-10.
    tols = [10.0^-k for k in 5:10]
    terrs = [maximum(abs, solve_adaptive(kepler_rhs!, u0, (0.0, TWO_PI); rtol = tol, atol = tol).y .- uT) for tol in tols]
    out["tol_slope"] = fit_order(tols, terrs)
    # An exact solution: the 6x6 nilpotent shift, solved exactly by DP5.
    shift!(du, u, t) = (for i in 1:5; du[i] = u[i+1]; end; du[6] = 0.0; nothing)
    exact = [sum(2.0^k / factorial(k) for k in 0:(6-i)) for i in 1:6]
    out["exact_linear_err"] = maximum(abs, solve_fixed(shift!, ones(6), (0.0, 2.0), 7)[1] .- exact)

    # ---- the question: cost at the required accuracy --------------------------------------------
    tol, err_d, nf_d = cheapest_setting(:dp54, ECC, NORBITS, TARGET)
    n, err_v, nf_v = cheapest_setting(:verlet, ECC, NORBITS, TARGET)
    out["tol_dp54"], out["err_dp54"], out["nf_dp54"] = tol, err_d, nf_d
    out["nper_verlet"], out["err_verlet"], out["nf_verlet"] = n, err_v, nf_v
    out["choice"] = nf_d <= nf_v ? "dp54" : "verlet"
    out["cost_ratio"] = nf_v / nf_d
    # The search grids bound the true minimal costs: each lies between the
    # failing neighbour's cost and the passing setting's.
    _, nf_d_fail = failing_neighbour(:dp54, ECC, NORBITS, tol)
    _, nf_v_fail = failing_neighbour(:verlet, ECC, NORBITS, n)
    out["cost_ratio_lo"] = nf_v_fail / nf_d
    out["cost_ratio_hi"] = nf_v / nf_d_fail

    # ---- uncertainty: the drift law and a perturbed assumption -----------------------------------
    out["drift_exp_dp54"] = drift_exponent(:dp54, ECC, tol)
    out["drift_exp_verlet"] = drift_exponent(:verlet, ECC, n)
    out["drift_fit_kmin"], out["drift_fit_kmax"] = 40, 1280
    rtol_, _, rnf_d = cheapest_setting(:dp54, ROBUST_ECC, NORBITS, TARGET)
    _, _, rnf_v = cheapest_setting(:verlet, ROBUST_ECC, NORBITS, TARGET)
    out["robust_e"] = ROBUST_ECC
    out["robust_cost_ratio"] = rnf_v / rnf_d
    out["robust_choice"] = rnf_d <= rnf_v ? "dp54" : "verlet"
    out["robust_holds"] = out["robust_choice"] == out["choice"] ? "holds" : "fails"

    # ---- validation of the proxy: positions against the exact orbit -------------------------------
    out["pos_err_dp54"] = position_error(:dp54, ECC, NORBITS, tol)
    out["pos_err_verlet"] = position_error(:verlet, ECC, NORBITS, n)

    # ---- where the conclusion was tested -----------------------------------------------------------
    out["valid_e_min"], out["valid_e_max"] = ECC, ROBUST_ECC
    out["valid_norbits_max"] = NORBITS
    return out
end
