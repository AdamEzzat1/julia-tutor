# The dualad case study (milestone 3). Write the functions below; their
# docstrings are the specification the hidden acceptance tests check.
#
# `tutor case check <dir> 3` loads this file into a module where your
# package is `DualAD`, runs the acceptance tests, and calls `study()` twice
# in fresh processes. Every value `study()` returns can be quoted in
# report.qmd with a `{claim:<id>}` tag; the checker compares the two.
# Nothing here may be random or read a clock (a clean re-run must give the
# same bits).

using DualAD

# The question's operating point. Do not change these: the acceptance tests
# check that study() reports them.
const X_LO, X_HI = 0.5, 1.0        # the interval the derivative is needed on
const NPOINTS = 101                # equally spaced points in it, ends included
const TARGET = 1e-12               # required max relative error of f'
const SHIFT = 96 * pi              # the perturbed assumption: the same interval moved by 48 periods

"""The function of the question: f(x) = exp(x) sin(x)."""
f(x) = exp(x) * sin(x)

"""
    exact_derivative(x) -> BigFloat

f'(x) = exp(x) (sin(x) + cos(x)), evaluated in 256-bit BigFloat at the
Float64 `x`: the ground truth, with an error far below Float64's eps.
"""
exact_derivative(x::Float64) = setprecision(BigFloat, 256) do
    b = big(x)
    exp(b) * (sin(b) + cos(b))
end

"""f'''(x) = 2 exp(x) (cos(x) - sin(x)) in BigFloat, for the error model's optimal step."""
exact_third(x::Float64) = setprecision(BigFloat, 256) do
    b = big(x)
    2 * exp(b) * (cos(b) - sin(b))
end

"""The `NPOINTS` equally spaced points of [lo, hi]."""
points(lo, hi) = collect(range(lo, hi; length = NPOINTS))

"""
    rule_step(x) -> Float64

The usual step for central differences when nothing is known about f:
cbrt(eps) * max(1, |x|).
"""
rule_step(x) = cbrt(eps()) * max(1.0, abs(x))

"""
    relerr(approx, exact::BigFloat) -> Float64

|approx - exact| / |exact|, computed in BigFloat and returned as Float64.
"""
function relerr(approx, exact::BigFloat)
    error("TODO: relerr")
end

"""
    max_error(method, xs; h = rule_step) -> (max, min)

The largest and the smallest relative error of f' over the points `xs`.
`method` is `:dual` (`derivative`) or `:central` (`central_diff` with the
step `h(x)`); anything else is an ArgumentError.
"""
function max_error(method::Symbol, xs; h = rule_step)
    error("TODO: max_error")
end

"""
    error_curve(x, hs) -> Vector{Float64}

The relative error of the central difference at `x` for each step in `hs`.
Plot it (or print it) before you choose fit ranges: it has two branches.
"""
function error_curve(x, hs)
    error("TODO: error_curve")
end

"""
    best_uniform_step(xs, hs) -> (h, err)

The step in `hs` that minimises the largest relative error over all of
`xs`, and that error. Look at the error at a single point first: why is
its minimum not the right answer?
"""
function best_uniform_step(xs, hs)
    error("TODO: best_uniform_step")
end

"""
    algorithm_derivative(iters) -> (value_err, deriv_err)

Relative errors of babylonian_sqrt(2) and of its dual derivative, after
`iters` Newton steps from 1, against sqrt(2) and 1 / (2 sqrt(2)) (compute
those in BigFloat).
"""
function algorithm_derivative(iters::Integer)
    error("TODO: algorithm_derivative")
end

"""
    study() -> Dict{String,Any}

Every number your report quotes, by claim id (`tutor case show dualad`
lists them with what each one is). The ids:

    x_lo x_hi npoints target
    rule_step cd_err cd_err_min dual_err choice grad_evals_dual grad_evals_central
    poly_err trunc_order trunc_fit_hmin trunc_fit_hmax round_slope round_fit_hmin round_fit_hmax
    cd_best_h cd_best_err cd_theory_h nested_err grad_err
    algo_value_err algo_deriv_err algo_iters
    robust_x_lo robust_x_hi robust_cd_err robust_dual_err robust_choice robust_holds
    valid_x_min valid_x_max

`rule_step` is the rule's step at x = 0.7. `choice` and `robust_choice` are
"dual" or "central" (central if it meets the budget: it is the cheaper
method to write and to run); `robust_holds` is "holds" or "fails".
`cd_theory_h` is (3 eps |f| / |f'''|)^(1/3) at the middle of the interval.
`algo_iters` is the fewest Newton steps after which the derivative's
relative error is at most 4 eps. The gradient claims use a function of 5
variables of your choice whose exact gradient you know.
"""
function study()
    out = Dict{String,Any}()
    out["x_lo"], out["x_hi"] = X_LO, X_HI
    out["npoints"] = NPOINTS
    out["target"] = TARGET
    error("TODO: study")
    return out
end
