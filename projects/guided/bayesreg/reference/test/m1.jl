# Exemplary student tests, milestone 1: the exact posterior.
using LinearAlgebra, Random

# Tiny data, drawn once with a fixed seed: 20 rows, intercept and slope.
function m1_data()
    X = hcat(ones(20), collect(range(-1, 1; length = 20)))
    y = X * [1.0, 2.0] .+ 0.5 .* randn(Xoshiro(1), 20)
    return X, y
end

@testset "posterior_exact" begin
    X, y = m1_data()
    s, t = 0.5, 2.0                    # not 1: a missing scale factor shows
    post = posterior_exact(X, y; sigma = s, tau = t)
    A = X' * X / s^2 + I / t^2
    # The formula again, another way (explicit inverse). Both are backward
    # stable, so they agree to about cond(A)·n·eps; cond(A) is about 3 here,
    # so 1e-12 leaves a wide margin.
    @test cond(A) < 10
    @test post.mean ≈ inv(A) * X' * y / s^2 rtol = 1e-12
    @test post.cov ≈ inv(A) rtol = 1e-12
    @test issymmetric(post.cov)
    @test isposdef(post.cov)
    @test post.cov * A ≈ I(2) atol = 1e-12        # entries O(1), same bound
    # A wide prior gives least squares: the prior moves the mean by about
    # s^2 / (tau^2 λmin(X'X)) ≈ 4e-14 relative at tau = 1e6.
    @test posterior_exact(X, y; sigma = s, tau = 1e6).mean ≈ X \ y rtol = 1e-10
    # A tight prior gives zero: the mean is tau^2 X'y / s^2 to first order.
    @test norm(posterior_exact(X, y; sigma = s, tau = 1e-6).mean) <= 2e-12 * norm(X' * y) / s^2
end

@testset "posterior_exact arguments" begin
    X, y = m1_data()
    @test_throws DimensionMismatch posterior_exact(X, y[1:19]; sigma = 0.5, tau = 2.0)
    @test_throws ArgumentError posterior_exact(X, y; sigma = -0.5, tau = 2.0)
    @test_throws ArgumentError posterior_exact(X, y; sigma = 0.5, tau = 0)
end
