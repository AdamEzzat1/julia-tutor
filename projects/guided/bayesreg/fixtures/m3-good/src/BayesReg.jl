module BayesReg

using Turing, LinearAlgebra, Random

export posterior_exact, regression_model, sample_posterior, coefficient_draws

function checked(X, y, sigma, tau)
    size(X, 1) == length(y) || throw(DimensionMismatch("X and y disagree in length"))
    sigma > 0 || throw(ArgumentError("sigma must be positive"))
    tau > 0 || throw(ArgumentError("tau must be positive"))
end

function posterior_exact(X::AbstractMatrix, y::AbstractVector; sigma, tau)
    checked(X, y, sigma, tau)
    A = Symmetric(X' * X / sigma^2 + I / tau^2)
    F = cholesky(A)
    return (mean = F \ (X' * y / sigma^2), cov = inv(F))
end

@model function linreg(X, y, sigma, tau)
    w ~ MvNormal(zeros(size(X, 2)), tau^2 * I)
    y ~ MvNormal(X * w, sigma^2 * I)
end

function regression_model(X, y; sigma, tau)
    checked(X, y, sigma, tau)
    return linreg(X, y, sigma, tau)
end

sample_posterior(rng::AbstractRNG, model; n = 1000) =
    sample(rng, model, NUTS(), n; progress = false, verbose = false)

function coefficient_draws(chain)
    W = vec(chain[@varname(w)])
    D = zeros(length(W), length(W[1]))
    for (i, w) in enumerate(W)
        D[i, :] = w
    end
    return D
end

end
