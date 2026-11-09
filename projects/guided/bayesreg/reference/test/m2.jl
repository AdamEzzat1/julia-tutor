# Exemplary student tests, milestone 2: the Turing model as a log density.
using LinearAlgebra, Random
using Turing: logprior, loglikelihood, logjoint

@testset "regression_model log density" begin
    X = hcat(ones(20), collect(range(-1, 1; length = 20)))
    y = X * [1.0, 2.0] .+ 0.5 .* randn(Xoshiro(2), 20)
    s, t = 0.5, 2.0                    # not 1: a standard deviation used as a variance shows
    model = regression_model(X, y; sigma = s, tau = t)
    w = [0.8, 1.7]
    lp = -log(2pi * t^2) - sum(abs2, w) / (2t^2)                     # k = 2
    ll = -10 * log(2pi * s^2) - sum(abs2, y - X * w) / (2s^2)          # n = 20
    # Sums of a few same-signed terms: rounding is a few n·eps (~1e-14);
    # 1e-12 is a safe bound.
    @test logprior(model, (w = w,)) ≈ lp rtol = 1e-12
    @test loglikelihood(model, (w = w,)) ≈ ll rtol = 1e-12
    @test logjoint(model, (w = w,)) ≈ lp + ll rtol = 1e-12
end
