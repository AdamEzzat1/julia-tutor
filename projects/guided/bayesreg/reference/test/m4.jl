# Exemplary student tests, milestone 4: predictive intervals.
using LinearAlgebra, Random, Statistics
using Turing: MvNormal

@testset "predictive_interval" begin
    # A posterior given directly: the function only needs mean and cov.
    post = (mean = [1.0, 2.0], cov = [0.04 0.01; 0.01 0.09])
    x, s = [1.0, 2.0], 0.5
    v = dot(x, post.cov * x)           # 0.44, comparable to s^2 = 0.25
    mu, sd = 5.0, sqrt(v + s^2)
    z90, z50 = 1.6448536269514722, 0.6744897501960817    # normal quantiles at 0.95 and 0.75
    # A few rounded operations on O(1) numbers, ends far from zero: 1e-12.
    lo, hi = predictive_interval(post, x; sigma = s)
    @test lo ≈ mu - z90 * sd rtol = 1e-12
    @test hi ≈ mu + z90 * sd rtol = 1e-12
    lo5, hi5 = predictive_interval(post, x; sigma = s, level = 0.5)
    @test hi5 ≈ mu + z50 * sd rtol = 1e-12
    @test_throws ArgumentError predictive_interval(post, x; sigma = s, level = 1.0)

    # From independent draws: each end within 5 standard errors. The SE
    # combines the error of the mean (v / n) and of the sample variance
    # (2 v^2 / n, through the square root's derivative 1 / (2 sd)).
    n = 4000
    D = permutedims(rand(Xoshiro(8), MvNormal(post.mean, post.cov), n))
    se = sqrt(v / n + z90^2 * 2v^2 / n / (4 * (v + s^2)))
    dlo, dhi = predictive_interval(D, x; sigma = s)
    @test abs(dlo - lo) <= 5se
    @test abs(dhi - hi) <= 5se
end
