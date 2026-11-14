# The odeint case study (milestone 3). Write the functions below; their
# docstrings are the specification the hidden acceptance tests check.
#
# `tutor case check <dir> 3` loads this file into a module where your
# package is `ODEInt`, runs the acceptance tests, and calls `study()` twice
# in fresh processes. Every value `study()` returns can be quoted in
# report.qmd with a `{claim:<id>}` tag; the checker compares the two.
# Nothing here may be random or read a clock (a clean re-run must give the
# same bits).

using ODEInt

const TWO_PI = 2 * pi

# The question's operating point. Do not change these: the acceptance tests
# check that study() reports them.
const ECC = 0.5            # eccentricity of the orbit
const NORBITS = 1000       # integration horizon, in orbits
const TARGET = 1e-6        # required max relative energy error over the horizon
const ROBUST_ECC = 0.6     # the perturbed assumption: a more eccentric orbit

"""
    max_energy_error(method, e, norbits, setting) -> (err, nf)

Integrate `norbits` orbits of eccentricity `e` from perihelion
(`kepler_initial(e)`) with `method`: `:dp54` is `solve_adaptive` with
`rtol = atol = setting`; `:verlet` is `solve_verlet` with `setting` steps
per orbit. Return the largest relative energy error |E(t) - E0| / |E0|
seen at any step (use the solvers' `observe` keyword) and the number of
right-hand-side (force) evaluations the solver reports.
"""
function max_energy_error(method::Symbol, e, norbits::Integer, setting)
    error("TODO: max_energy_error")
end

"""
    drift_exponent(method, e, setting; orbits = ...) -> Float64

The growth exponent of the energy error: the fitted slope (`fit_order`) of
log(max_energy_error up to k orbits) on log(k), over the orbit counts in
`orbits`. Theory says 1 for a Runge-Kutta method and 0 for a symplectic
one. Choose the default `orbits` yourself and report it: the first orbits
can mislead (look at the numbers before you fit).
"""
function drift_exponent(method::Symbol, e, setting; orbits = Int[])
    error("TODO: drift_exponent")
end

"""
    cheapest_setting(method, e, norbits, target) -> (setting, err, nf)

The cheapest setting you can find that keeps `max_energy_error` at or below
`target`, with its error and cost. The acceptance tests check, for DP5(4),
that no tolerance on the quarter-decade grid 10^(-j/4) from 1e-6 down to
yours meets the target (a finer grid of your own is fine), and for
Verlet, that 10% fewer steps per orbit fails it. Start DP5(4) at 1e-6, no
looser: over 1000 orbits at 1e-4 the orbit decays towards a collision and
the step count explodes. Look at the errors along the way: they are not
monotone in the tolerance.
"""
function cheapest_setting(method::Symbol, e, norbits::Integer, target)
    error("TODO: cheapest_setting")
end

"""
    study() -> Dict{String,Any}

Every number your report quotes, by claim id (`tutor case show odeint`
lists them with what each one is). The ids:

    eccentricity norbits target
    tol_dp54 err_dp54 nf_dp54 nper_verlet err_verlet nf_verlet
    choice cost_ratio cost_ratio_lo cost_ratio_hi
    conv_order conv_fit_hmin conv_fit_hmax verlet_order verlet_fit_hmin verlet_fit_hmax
    tol_slope exact_linear_err
    pos_err_dp54 pos_err_verlet
    drift_exp_dp54 drift_exp_verlet drift_fit_kmin drift_fit_kmax
    robust_e robust_cost_ratio robust_choice robust_holds
    valid_e_min valid_e_max valid_norbits_max

`choice` and `robust_choice` are "dp54" or "verlet"; `robust_holds` is
"holds" or "fails". `cost_ratio_lo` and `cost_ratio_hi` bound the cost
ratio using your search grid: the true cheapest cost of each method lies
between the cost of the setting that just failed and the one that passed.
"""
function study()
    out = Dict{String,Any}()
    out["eccentricity"] = ECC
    out["norbits"] = NORBITS
    out["target"] = TARGET
    error("TODO: study")
    return out
end
