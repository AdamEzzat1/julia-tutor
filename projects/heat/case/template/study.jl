# The heat case study (milestone 3). Write the functions below; their
# docstrings are the specification the hidden acceptance tests check.
#
# `tutor case check <dir> 3` loads this file into a module where your
# package is `Heat1D`, runs the acceptance tests, and calls `study()` twice
# in fresh processes. Every value `study()` returns can be quoted in
# report.qmd with a `{claim:<id>}` tag; the checker compares the two.
# Nothing here may be random or read a clock (a clean re-run must give the
# same bits).

using Heat1D

# The question's operating point. Do not change these: the acceptance tests
# check that study() reports them.
const KAPPA = 1.0          # diffusivity
const TFINAL = 0.01        # the time the midpoint temperature is needed at
const TARGET = 1e-5        # required relative error of the midpoint temperature
const NFINE = 2^14         # time steps of a fine reference run (its time error is ~1e-10 relative)
const NS = [2^k - 1 for k in 4:11]          # the space grids to try: 15 ... 2047 interior points
const STEPS = [2^j for j in 0:20]           # the step counts to try for the implicit methods

"""The smooth initial profile of the question: u0 = sin(pi x)."""
smooth() = HeatProblem(KAPPA, x -> sinpi(x))

"""
The rough initial profile of the perturbed assumption: 1 on (1/4, 3/4), 0
outside, and 1/2 at the two jumps (every grid here has N + 1 a power of 2,
so the jumps are grid points).
"""
tophat() = HeatProblem(KAPPA, x -> (0.25 < x < 0.75) ? 1.0 : (x == 0.25 || x == 0.75) ? 0.5 : 0.0)

problem(ic::Symbol) = ic === :smooth ? smooth() : tophat()

"""The midpoint temperature (N odd, so the midpoint is grid point (N + 1) / 2) and the cost."""
function midpoint(ic::Symbol, N, nsteps, method)
    _, u, cost = solve_heat(problem(ic), N, nsteps, TFINAL; method = method)
    return u[(N + 1) ÷ 2], cost
end

"""
    exact_mid(ic) -> Float64

The exact midpoint temperature at TFINAL for `ic` = :smooth or :tophat,
from the Fourier sine series of the initial profile: the sum over k of
b_k exp(-k^2 pi^2 kappa T) sin(k pi / 2). Work out b_k for the top hat, and
how many terms you need.
"""
function exact_mid(ic::Symbol)
    error("TODO: exact_mid")
end

"""
    space_error(ic, N) -> Float64

The relative error of the midpoint temperature due to the space grid
alone: Crank-Nicolson with NFINE time steps against the exact value.
"""
function space_error(ic::Symbol, N)
    error("TODO: space_error")
end

"""
    time_error(ic, N, nsteps, method) -> Float64

The relative error due to the time stepping alone: the method with
`nsteps` steps against the fine run (NFINE Crank-Nicolson steps) on the
same grid, divided by |exact_mid(ic)|.
"""
function time_error(ic::Symbol, N, nsteps, method)
    error("TODO: time_error")
end

"""
    cheapest(ic, method) -> (N, nsteps, cost, space_err, time_err)

The cheapest setting that meets the budget, with the budget split: space
error <= TARGET / 2 and time error <= TARGET / 2. N is the first grid in
NS meeting the space half; then the first step count meeting the time
half (from STEPS for :be and :cn; for :ftcs, start at the stability limit
r = kappa dt / dx^2 <= 1/2 and double). Why not just ask for a total error
below TARGET? Try it on 31 points first.
"""
function cheapest(ic::Symbol, method::Symbol)
    error("TODO: cheapest")
end

"""
    stability_limit(N; nsteps = 200) -> Float64

FTCS's stability limit in r = kappa dt / dx^2 on N interior points,
measured: bisect on r (to 1e-7) between a run of `nsteps` steps that does
not grow the grid's fastest mode sin(N pi x) and one that does.
"""
function stability_limit(N::Integer; nsteps::Integer = 200)
    error("TODO: stability_limit")
end

"""
    local_maxima(u) -> Int

The number of strict local maxima of a profile (a plateau counts once),
with the boundary value 0 outside both ends.
"""
function local_maxima(u)
    error("TODO: local_maxima")
end

"""
    study() -> Dict{String,Any}

Every number your report quotes, by claim id (`tutor case show heat` lists
them with what each one is). The ids:

    kappa t_final target exact_mid
    n_space space_err ns_ftcs cost_ftcs time_err_ftcs ns_be cost_be ns_cn cost_cn time_err_cn
    choice cost_ratio cancel_n cancel_ns cancel_total_err cancel_space_err
    mms_space_order mms_dx_min mms_dx_max mms_time_order_cn mms_time_order_be mms_dt_min mms_dt_max
    quad_err cfl_measured cfl_theory
    cn_peaks be_peaks cn_peak_excess
    robust_n_space robust_ns_cn robust_cost_cn robust_cost_ftcs robust_cost_be
    robust_choice robust_cost_ratio robust_holds
    valid_n_max valid_target

`choice` and `robust_choice` are "ftcs", "be" or "cn"; `robust_holds` is
"holds" or "fails". `cost_ratio` is FTCS's cost over the chosen method's.
The cancellation claims: on 31 points, the step count in STEPS[1:12] whose
Crank-Nicolson run has the smallest total error, that error, and the space
error of 31 points. The orders come from `mms_problem(KAPPA)` to t = 0.5,
with the fit ranges you choose. `quad_err` is the largest error on a
steady quadratic (u = x^2 with source -2 kappa). `cfl_*` are for 31 points.
The peaks are of the top hat on 511 points after ONE step to TFINAL with
:cn and with :be; `cn_peak_excess` is Crank-Nicolson's maximum minus its
midpoint value. `valid_n_max` is the finest grid any choice used.
"""
function study()
    out = Dict{String,Any}()
    out["kappa"], out["t_final"], out["target"] = KAPPA, TFINAL, TARGET
    error("TODO: study")
    return out
end
