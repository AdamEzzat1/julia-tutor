"""
    BayesReg

Reference solution of the `bayesreg` guided project: Bayesian linear
regression with a normal prior `w ~ N(0, tau^2 I)` on the coefficients and
known noise `sigma`, solved twice. Once exactly (the conjugate posterior is
normal, in closed form) and once by sampling a Turing.jl model with NUTS; the
exact answer is what the samples are checked against.
"""
module BayesReg

using Turing, LinearAlgebra, Random, Statistics

export posterior_exact, regression_model, sample_posterior, coefficient_draws, predictive_interval

# ---- milestone 1: the exact posterior ----------------------------------------------------

function check_args(X::AbstractMatrix, y::AbstractVector, sigma::Real, tau::Real)
    size(X, 1) == length(y) ||
        throw(DimensionMismatch("X has $(size(X, 1)) rows but y has $(length(y)) entries"))
    sigma > 0 || throw(ArgumentError("sigma must be positive, got $sigma"))
    tau > 0 || throw(ArgumentError("tau must be positive, got $tau"))
    return nothing
end

"""
    posterior_exact(X, y; sigma, tau) -> (mean = m, cov = C)

The posterior of the coefficients `w` for `y ~ N(X w, sigma^2 I)` with the
prior `w ~ N(0, tau^2 I)`: normal, with precision
`A = X'X / sigma^2 + I / tau^2`, covariance `C = inv(A)` and mean
`m = A \\ (X'y / sigma^2)`.
"""
function posterior_exact(X::AbstractMatrix, y::AbstractVector; sigma::Real, tau::Real)
    check_args(X, y, sigma, tau)
    k = size(X, 2)
    A = Symmetric(X' * X / sigma^2 + I(k) / tau^2)
    F = cholesky(A)            # A is symmetric positive definite: no explicit inverse for the mean
    m = F \ (X' * y / sigma^2)
    C = inv(F)                 # LAPACK potri: the result is exactly symmetric
    return (mean = m, cov = C)
end

# ---- milestone 2: the Turing model ---------------------------------------------------------

# MvNormal's second argument is a covariance matrix: variances, not standard deviations.
@model function linear_regression(X, y, sigma, tau)
    k = size(X, 2)
    w ~ MvNormal(zeros(k), tau^2 * I)
    y ~ MvNormal(X * w, sigma^2 * I)
end

"""
    regression_model(X, y; sigma, tau) -> DynamicPPL.Model

The same model in Turing: `w ~ MvNormal(0, tau^2 I)`, and the observed `y ~
MvNormal(X w, sigma^2 I)`.
"""
function regression_model(X::AbstractMatrix, y::AbstractVector; sigma::Real, tau::Real)
    check_args(X, y, sigma, tau)
    return linear_regression(X, y, sigma, tau)
end

# ---- milestone 3: sampling -------------------------------------------------------------------

"""
    sample_posterior(rng, model; n = 1000) -> chain

`n` NUTS draws from `model`'s posterior, using `rng` for every random choice
(so the same seed gives the same chain), with no progress bar.
"""
function sample_posterior(rng::AbstractRNG, model; n::Integer = 1000)
    return sample(rng, model, NUTS(), n; progress = false, verbose = false)
end

"""
    coefficient_draws(chain) -> Matrix{Float64}

The draws of `w` as an `n × k` matrix: row `i` is draw `i`, column `j` is `w[j]`.
"""
function coefficient_draws(chain)
    ws = vec(chain[@varname(w)])           # one coefficient vector per draw
    return permutedims(reduce(hcat, ws))
end

# ---- milestone 4: prediction -----------------------------------------------------------------

function check_level(level::Real)
    0 < level < 1 || throw(ArgumentError("level must be in (0, 1), got $level"))
    return nothing
end

# The central interval of N(mu, s^2) with probability `level` between its ends.
function central_interval(mu::Real, s::Real, level::Real)
    z = quantile(Normal(), (1 + level) / 2)
    return (Float64(mu - z * s), Float64(mu + z * s))
end

"""
    predictive_interval(post, xnew; sigma, level = 0.9) -> (lo, hi)

Central `level` interval of the posterior predictive of `y` at `xnew` for the
exact posterior `post = (mean = m, cov = C)`: normal with mean `xnew'm` and
variance `xnew'C xnew + sigma^2` (uncertainty in `w` plus the noise).
"""
function predictive_interval(post::NamedTuple, xnew::AbstractVector; sigma::Real, level::Real = 0.9)
    check_level(level)
    mu = dot(xnew, post.mean)
    v = dot(xnew, post.cov * xnew) + sigma^2
    return central_interval(mu, sqrt(v), level)
end

"""
    predictive_interval(draws, xnew; sigma, level = 0.9) -> (lo, hi)

The same from an `n × k` matrix of posterior draws of `w`: the mean and
variance of `xnew'w` over the draws, plus the noise variance.
"""
function predictive_interval(draws::AbstractMatrix, xnew::AbstractVector; sigma::Real, level::Real = 0.9)
    check_level(level)
    f = draws * xnew
    mu = mean(f)
    v = var(f) + sigma^2
    return central_interval(mu, sqrt(v), level)
end

end # module BayesReg
