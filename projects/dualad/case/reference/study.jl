# The dualad case study (milestone 3), reference version.
#
# Loaded by the case checker into a module where your package is `DualAD`.
# Every value `study()` returns can be quoted in report.qmd with a
# `{claim:<id>}` tag; the checker re-runs this file in a fresh process twice
# and compares. Nothing here may be random or read a clock.

using DualAD

# ---- the operating point of the question ------------------------------------------------------

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

"""|approx - exact| / |exact| as a Float64."""
relerr(approx, exact::BigFloat) = Float64(abs(big(approx) - exact) / abs(exact))

"""The `NPOINTS` equally spaced points of [lo, hi]."""
points(lo, hi) = collect(range(lo, hi; length = NPOINTS))

"""
    rule_step(x) -> Float64

The usual step for central differences when nothing is known about f:
cbrt(eps) * max(1, |x|). It balances truncation (h^2) against rounding
(eps / h) for a function whose scale of variation is max(1, |x|).
"""
rule_step(x) = cbrt(eps()) * max(1.0, abs(x))

"""
    max_error(method, xs; h = rule_step) -> (max, min)

The largest and the smallest relative error of f' over the points `xs`.
`method` is `:dual` (`derivative`) or `:central` (`central_diff` with the
step `h(x)`).
"""
function max_error(method::Symbol, xs; h = rule_step)
    errs = map(xs) do x
        approx = method === :dual ? derivative(f, x) :
                 method === :central ? central_diff(f, x, h(x)) :
                 throw(ArgumentError("method must be :dual or :central"))
        relerr(approx, exact_derivative(x))
    end
    return maximum(errs), minimum(errs)
end

"""
    error_curve(x, hs) -> Vector{Float64}

The relative error of the central difference at `x` for each step in `hs`.
"""
error_curve(x, hs) = [relerr(central_diff(f, x, h), exact_derivative(x)) for h in hs]

"""
    best_uniform_step(xs, hs) -> (h, err)

The step in `hs` that minimises the largest relative error over all of
`xs`, and that error. The minimum at a single point is not used: there a
lucky cancellation of rounding errors can give an error ten times smaller
than at its neighbours (measured at x = 0.7: 5.9e-13 at h = 2^-17 against
4.5e-12 at 2^-16 and 2^-18).
"""
function best_uniform_step(xs, hs)
    worst = [maximum(relerr(central_diff(f, x, h), exact_derivative(x)) for x in xs) for h in hs]
    i = argmin(worst)
    return hs[i], worst[i]
end

"""
    algorithm_derivative(iters) -> (value_err, deriv_err)

Relative errors of babylonian_sqrt(2) and of its dual derivative, after
`iters` Newton steps from 1, against sqrt(2) and 1 / (2 sqrt(2)).
"""
function algorithm_derivative(iters::Integer)
    d = babylonian_sqrt(Dual(2.0, 1.0); iters = iters)
    r = setprecision(BigFloat, 256) do
        sqrt(big(2.0))
    end
    return relerr(value(d), r), relerr(partial(d), 1 / (2 * r))
end

function study()
    out = Dict{String,Any}()
    out["x_lo"], out["x_hi"] = X_LO, X_HI
    out["npoints"] = NPOINTS
    out["target"] = TARGET
    xs = points(X_LO, X_HI)

    # ---- the question: the largest error over the interval, each method --------------------------
    out["rule_step"] = rule_step(0.7)
    out["cd_err"], out["cd_err_min"] = max_error(:central, xs)
    out["dual_err"], _ = max_error(:dual, xs)
    out["choice"] = out["cd_err"] <= TARGET ? "central" : "dual"

    # ---- verification ------------------------------------------------------------------------------
    # A polynomial with small integer coefficients at a dyadic point: every
    # operation is exact in Float64, so the dual derivative must be exact.
    p(x) = 3x^5 - 2x^3 + x^2 - 7x + 4
    dp(x) = 15x^4 - 6x^2 + 2x - 7
    out["poly_err"] = abs(derivative(p, 0.75) - dp(0.75))
    # The central difference's error model at x = 0.7: slope 2 where
    # truncation dominates, slope -1 where rounding does.
    ths = [2.0^-k for k in 3:8]
    out["trunc_order"] = fit_order(ths, error_curve(0.7, ths))
    out["trunc_fit_hmin"], out["trunc_fit_hmax"] = minimum(ths), maximum(ths)
    rhs = [2.0^-k for k in 30:45]
    out["round_slope"] = fit_order(rhs, error_curve(0.7, rhs))
    out["round_fit_hmin"], out["round_fit_hmax"] = minimum(rhs), maximum(rhs)
    # The best uniform step on a quarter-octave grid, against the model's
    # optimum h* = (3 eps |f| / |f'''|)^(1/3) at the middle of the interval.
    grid = [2.0^(-k / 4) for k in 40:100]
    out["cd_best_h"], out["cd_best_err"] = best_uniform_step(xs, grid)
    out["cd_theory_h"] = Float64(cbrt(3 * eps() * abs(big(f(0.75))) / abs(exact_third(0.75))))
    # Nested duals give the second derivative: (exp sin)'' = 2 exp cos.
    d2 = derivative(x -> derivative(f, x), 0.7)
    out["nested_err"] = relerr(d2, setprecision(() -> 2 * exp(big(0.7)) * cos(big(0.7)), BigFloat, 256))
    # A gradient in 5 variables against its exact components.
    g(x) = sum(f(x[i]) for i in eachindex(x)) + x[1] * x[end]
    x5 = collect(range(0.1, 1.0; length = 5))
    gd = gradient(g, x5)
    ge = [exact_derivative(x5[i]) + (i == 1 ? big(x5[end]) : i == 5 ? big(x5[1]) : big(0.0)) for i in 1:5]
    out["grad_err"] = maximum(relerr(gd[i], ge[i]) for i in 1:5)
    out["grad_evals_dual"] = length(x5)
    out["grad_evals_central"] = 2 * length(x5)

    # ---- validation: the derivative of the code is not always the derivative of the math ----------
    out["algo_value_err"], out["algo_deriv_err"] = algorithm_derivative(3)
    out["algo_iters"] = findfirst(k -> algorithm_derivative(k)[2] <= 4 * eps(), 1:20)

    # ---- uncertainty: the same interval far from the origin ----------------------------------------
    rxs = points(X_LO + SHIFT, X_HI + SHIFT)
    out["robust_x_lo"], out["robust_x_hi"] = first(rxs), last(rxs)
    out["robust_cd_err"], _ = max_error(:central, rxs)
    out["robust_dual_err"], _ = max_error(:dual, rxs)
    out["robust_choice"] = out["robust_cd_err"] <= TARGET ? "central" : "dual"
    out["robust_holds"] = out["robust_choice"] == out["choice"] ? "holds" : "fails"

    # ---- where the conclusion was tested ------------------------------------------------------------
    out["valid_x_min"], out["valid_x_max"] = X_LO, last(rxs)
    return out
end
