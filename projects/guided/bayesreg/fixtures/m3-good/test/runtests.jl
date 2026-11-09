using BayesReg, Test, LinearAlgebra, Random, Statistics
using Turing: logprior, loglikelihood, @varname
using Turing.FlexiChains: mcse

function data()
    X = hcat(ones(20), collect(range(-1, 1; length = 20)))
    y = X * [1.0, 2.0] .+ 0.5 .* randn(Xoshiro(5), 20)
    return X, y
end

@testset "exact posterior" begin
    X, y = data()
    s, t = 0.5, 2.0
    post = posterior_exact(X, y; sigma = s, tau = t)
    A = X' * X / s^2 + I / t^2
    # cond(A) ~ 3; both ways of computing are backward stable: 1e-12 is safe
    @test post.mean ≈ inv(A) * X' * y / s^2 rtol = 1e-12
    @test post.cov ≈ inv(A) rtol = 1e-12
    @test issymmetric(post.cov)
    @test_throws ArgumentError posterior_exact(X, y; sigma = -1.0, tau = t)
    @test_throws DimensionMismatch posterior_exact(X, y[1:5]; sigma = s, tau = t)
end

@testset "model" begin
    X, y = data()
    s, t = 0.5, 2.0
    m = regression_model(X, y; sigma = s, tau = t)
    w = [0.9, 2.2]
    # sums of 2 and 20 same-signed terms: rounding ~ n eps, 1e-12 is safe
    @test logprior(m, (w = w,)) ≈ -log(2pi * t^2) - sum(abs2, w) / (2t^2) rtol = 1e-12
    @test loglikelihood(m, (w = w,)) ≈ -10 * log(2pi * s^2) - sum(abs2, y - X * w) / (2s^2) rtol = 1e-12
end

@testset "sampling" begin
    X, y = data()
    m = regression_model(X, y; sigma = 0.5, tau = 2.0)
    @test isequal(coefficient_draws(sample_posterior(Xoshiro(1), m; n = 50)),
                  coefficient_draws(sample_posterior(Xoshiro(1), m; n = 50)))
    c = sample_posterior(Xoshiro(2), m; n = 600)
    D = coefficient_draws(c)
    @test size(D) == (600, 2)
    # 4 MCSE: a correct sampler fails with probability ~6e-5 per coefficient; fixed seed
    post = posterior_exact(X, y; sigma = 0.5, tau = 2.0)
    for j in 1:2
        @test abs(mean(D[:, j]) - post.mean[j]) <= 4 * mcse(c)[@varname(w[j])]
    end
end
