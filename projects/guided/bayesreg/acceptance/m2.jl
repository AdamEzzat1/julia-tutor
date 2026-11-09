# Acceptance, milestone 2: regression_model. One @testset per behaviour id.
#
# Tolerance: each log density is a sum of a log-normalising term and a sum
# of squares, all terms of the same sign here, so the hand formula and
# Distributions' MvNormal (a Cholesky of a multiple of I, then a quadratic
# form) each carry a relative rounding error of at most a few n·eps
# (n = 20: about 1e-14). RTOL = 1e-12 leaves a factor 100 above that, and is
# far below the change from confusing a standard deviation with a variance
# (tens of percent at sigma = 0.5, tau = 2).
using BayesReg, Test, LinearAlgebra, Random
using Turing: logprior, loglikelihood, logjoint

const X = hcat(ones(20), collect(range(-1, 1; length = 20)))
const Y = X * [1.0, 2.0] .+ 0.5 .* randn(Xoshiro(11), 20)   # fixed seed
const RTOL = 1e-12

hand_logprior(w, tau) = -length(w) / 2 * log(2pi * tau^2) - sum(abs2, w) / (2tau^2)
hand_loglik(w, sigma) = -length(Y) / 2 * log(2pi * sigma^2) - sum(abs2, Y - X * w) / (2sigma^2)

const CASES = ((0.5, 2.0), (0.3, 0.6))
const WS = ([1.0, 2.0], [0.4, -1.3], [2.5, 0.5])

@testset "model-prior" begin
    for (s, t) in CASES, w in WS
        model = regression_model(X, Y; sigma = s, tau = t)
        @test isapprox(logprior(model, (w = w,)), hand_logprior(w, t); rtol = RTOL)
    end
end

@testset "model-likelihood" begin
    for (s, t) in CASES, w in WS
        model = regression_model(X, Y; sigma = s, tau = t)
        @test isapprox(loglikelihood(model, (w = w,)), hand_loglik(w, s); rtol = RTOL)
        @test isapprox(logjoint(model, (w = w,)), hand_logprior(w, t) + hand_loglik(w, s); rtol = RTOL)
    end
end
