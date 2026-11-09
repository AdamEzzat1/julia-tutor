# Acceptance, milestone 3: sample_posterior and coefficient_draws. One @testset per behaviour id.
#
# Agreement bound: |sampled mean - exact mean| <= 4 MCSE per coefficient,
# with MCSE = posterior sd / sqrt(ESS) as FlexiChains estimates it. If the
# sampling error is normal with that standard error, a correct sampler fails
# this with probability 2·(1 - Φ(4)) ≈ 6.3e-5 per coefficient (1.3e-4 for
# both). The seed is fixed, so the verdict is the same on every run;
# calibrated: seeds 1-6 with n = 1000 gave |error| / MCSE of at most 2.05,
# and seed 3 (used here) gives 0.83 and 0.90, a margin of over 3 MCSE.
# A sampler that draws from the prior instead is about 17 MCSE off.
using BayesReg, Test, LinearAlgebra, Random, Statistics
using Turing: @varname
using Turing.FlexiChains: mcse

const X = hcat(ones(20), collect(range(-1, 1; length = 20)))
const Y = X * [1.0, 2.0] .+ 0.5 .* randn(Xoshiro(11), 20)   # fixed seed
const MODEL = regression_model(X, Y; sigma = 0.5, tau = 2.0)

@testset "sample-reproducible" begin
    a = coefficient_draws(sample_posterior(Xoshiro(5), MODEL; n = 100))
    b = coefficient_draws(sample_posterior(Xoshiro(5), MODEL; n = 100))
    @test isequal(a, b)                # same seed, same arithmetic: identical draws
end

@testset "sample-shape" begin
    c = sample_posterior(Xoshiro(6), MODEL; n = 150)
    D = coefficient_draws(c)
    @test D isa AbstractMatrix{Float64}
    @test size(D) == (150, 2)
    @test isequal(D[:, 1], vec(c[@varname(w[1])]))   # same numbers, rearranged: exact
    @test isequal(D[:, 2], vec(c[@varname(w[2])]))
    @test size(coefficient_draws(sample_posterior(Xoshiro(7), MODEL)), 1) == 1000
end

@testset "posterior-agrees" begin
    post = posterior_exact(X, Y; sigma = 0.5, tau = 2.0)
    c = sample_posterior(Xoshiro(3), MODEL; n = 1000)
    D = coefficient_draws(c)
    for j in 1:2
        se = mcse(c)[@varname(w[j])]
        @test abs(mean(D[:, j]) - post.mean[j]) <= 4 * se
    end
end
