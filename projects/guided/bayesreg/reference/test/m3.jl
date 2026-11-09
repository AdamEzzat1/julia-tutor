# Exemplary student tests, milestone 3: NUTS against the exact posterior.
using LinearAlgebra, Random, Statistics
using Turing: @varname
using Turing.FlexiChains: mcse

@testset "sample_posterior" begin
    X = hcat(ones(20), collect(range(-1, 1; length = 20)))
    y = X * [1.0, 2.0] .+ 0.5 .* randn(Xoshiro(3), 20)
    model = regression_model(X, y; sigma = 0.5, tau = 2.0)

    # Same seed, same draws (exact: the same arithmetic runs twice).
    a = coefficient_draws(sample_posterior(Xoshiro(9), model; n = 100))
    @test a == coefficient_draws(sample_posterior(Xoshiro(9), model; n = 100))

    # n draws, one column per coefficient.
    c = sample_posterior(Xoshiro(4), model; n = 800)
    D = coefficient_draws(c)
    @test size(D) == (800, 2)

    # Within 4 MCSE of the exact mean: fails with probability ~6e-5 per
    # coefficient for a correct sampler (normal approximation); the seed is
    # fixed, so the verdict does not change between runs.
    post = posterior_exact(X, y; sigma = 0.5, tau = 2.0)
    for j in 1:2
        @test abs(mean(D[:, j]) - post.mean[j]) <= 4 * mcse(c)[@varname(w[j])]
    end
end
