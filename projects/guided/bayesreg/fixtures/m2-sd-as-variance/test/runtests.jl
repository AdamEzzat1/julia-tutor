# The code and the tests share one misunderstanding: they treat the second
# argument of MvNormal as standard deviations, so the hand formula uses
# sigma where the variance sigma^2 belongs.
using BayesReg, Test, LinearAlgebra, Random
using Turing: logprior, loglikelihood

@testset "posterior" begin
    X = hcat(ones(20), collect(range(-1, 1; length = 20)))
    y = X * [1.0, 2.0] .+ 0.5 .* randn(Xoshiro(4), 20)
    post = posterior_exact(X, y; sigma = 0.5, tau = 2.0)
    A = X' * X / 0.25 + I / 4
    @test post.mean ≈ inv(A) * X' * y / 0.25 rtol = 1e-12    # cond(A) ~ 3
    @test post.cov ≈ inv(A) rtol = 1e-12
    @test_throws ArgumentError posterior_exact(X, y; sigma = 0.5, tau = -1.0)
end

@testset "model" begin
    X = hcat(ones(20), collect(range(-1, 1; length = 20)))
    y = X * [1.0, 2.0] .+ 0.5 .* randn(Xoshiro(4), 20)
    s, t = 0.5, 2.0
    m = regression_model(X, y; sigma = s, tau = t)
    w = [1.0, 2.0]
    @test logprior(m, (w = w,)) ≈ -log(2pi * t) - sum(abs2, w) / (2t) rtol = 1e-12
    @test loglikelihood(m, (w = w,)) ≈ -10 * log(2pi * s) - sum(abs2, y - X * w) / (2s) rtol = 1e-12
end
