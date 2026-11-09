# Acceptance, milestone 1: posterior_exact. One @testset per behaviour id.
#
# Ground truth is the same formula evaluated in 256-bit BigFloat on the same
# Float64 inputs, so its own error is negligible. Tolerance for the Float64
# result (derived, not tuned): forming X'y rounds a sum of n products, with
# relative error at most n·eps·|X|'|y| / |X'y| (the slope column changes
# sign, so this ratio is not 1); forming A rounds sums of n same-signed
# terms (n·eps); the Cholesky solve and inverse are backward stable, so the
# forward error is at most about cond(A) times the sum of those. RTOL below
# is 4 times that bound (it comes to about 1e-13 here).
using BayesReg, Test, LinearAlgebra, Random

const X = hcat(ones(20), collect(range(-1, 1; length = 20)))
const Y = X * [1.0, 2.0] .+ 0.5 .* randn(Xoshiro(11), 20)   # fixed seed
const N = length(Y)

precision_matrix(s, t) = X' * X / s^2 + I / t^2
function exact_big(s, t)
    Xb, yb = big.(X), big.(Y)
    Ab = Xb' * Xb / big(s)^2 + I / big(t)^2
    return Ab \ (Xb' * yb / big(s)^2), inv(Ab)
end
function rtol_for(s, t)
    A = precision_matrix(s, t)
    cancel = norm(abs.(X)' * abs.(Y)) / norm(X' * Y)
    return 4 * cond(A) * N * eps() * (cancel + 1)
end

@testset "posterior-mean" begin
    for (s, t) in ((0.5, 2.0), (0.3, 0.7), (1.5, 5.0))
        post = posterior_exact(X, Y; sigma = s, tau = t)
        mb, _ = exact_big(s, t)
        @test post.mean isa AbstractVector{Float64}
        @test length(post.mean) == 2
        @test isapprox(post.mean, Float64.(mb); rtol = rtol_for(s, t))
    end
    # Flat prior: the prior term I / tau^2 shifts the mean by a relative
    # sigma^2 / (tau^2 λmin(X'X)) ≈ 4e-14 at tau = 1e6, and rounding adds about
    # cond(X'X)·n·eps ≈ 1e-14; 1e-10 is far above both.
    flat = posterior_exact(X, Y; sigma = 0.5, tau = 1e6)
    @test isapprox(flat.mean, X \ Y; rtol = 1e-10)
    # Tight prior: the mean is tau^2 X'y / sigma^2 to first order (the data
    # term in A is 1e-12 relative to I / tau^2 at tau = 1e-6), so its norm is
    # below twice that size.
    tight = posterior_exact(X, Y; sigma = 0.5, tau = 1e-6)
    @test norm(tight.mean) <= 2 * 1e-12 * norm(X' * Y) / 0.25
end

@testset "posterior-cov" begin
    for (s, t) in ((0.5, 2.0), (0.3, 0.7), (1.5, 5.0))
        post = posterior_exact(X, Y; sigma = s, tau = t)
        A = precision_matrix(s, t)
        _, Cb = exact_big(s, t)
        C = post.cov
        @test size(C) == (2, 2)
        @test issymmetric(C)          # exactly: a covariance is symmetric by definition
        @test isposdef(C)
        @test isapprox(C, Float64.(Cb); rtol = rtol_for(s, t))
        @test isapprox(C * A, Matrix(1.0I, 2, 2); atol = rtol_for(s, t))   # entries of C*A are O(1)
    end
end

@testset "posterior-args" begin
    @test_throws DimensionMismatch posterior_exact(X, Y[1:end-1]; sigma = 0.5, tau = 2.0)
    @test_throws ArgumentError posterior_exact(X, Y; sigma = -0.5, tau = 2.0)
    @test_throws ArgumentError posterior_exact(X, Y; sigma = 0, tau = 2.0)
    @test_throws ArgumentError posterior_exact(X, Y; sigma = 0.5, tau = 0)
    @test_throws ArgumentError posterior_exact(X, Y; sigma = 0.5, tau = -2.0)
end
