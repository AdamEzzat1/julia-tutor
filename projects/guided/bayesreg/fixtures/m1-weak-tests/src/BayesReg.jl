module BayesReg

using LinearAlgebra

export posterior_exact

function posterior_exact(X::AbstractMatrix, y::AbstractVector; sigma, tau)
    size(X, 1) == length(y) || throw(DimensionMismatch("X and y disagree in length"))
    (sigma > 0 && tau > 0) || throw(ArgumentError("sigma and tau must be positive"))
    A = Symmetric(X' * X ./ sigma^2 + I ./ tau^2)
    F = cholesky(A)
    return (mean = F \ (X' * y ./ sigma^2), cov = inv(F))
end

end
