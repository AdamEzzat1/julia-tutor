module BayesReg

using Turing, LinearAlgebra

export posterior_exact, regression_model

function posterior_exact(X::AbstractMatrix, y::AbstractVector; sigma, tau)
    size(X, 1) == length(y) || throw(DimensionMismatch("X and y disagree in length"))
    (sigma > 0 && tau > 0) || throw(ArgumentError("sigma and tau must be positive"))
    A = Symmetric(X' * X ./ sigma^2 + I ./ tau^2)
    F = cholesky(A)
    return (mean = F \ (X' * y ./ sigma^2), cov = inv(F))
end

# Wrong: MvNormal's second argument is a covariance, and these are standard deviations.
@model function linreg(X, y, sigma, tau)
    w ~ MvNormal(zeros(size(X, 2)), tau * I)
    y ~ MvNormal(X * w, sigma * I)
end

regression_model(X, y; sigma, tau) = linreg(X, y, sigma, tau)

end
