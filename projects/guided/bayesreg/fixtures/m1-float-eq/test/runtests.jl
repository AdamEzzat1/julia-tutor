# Correct code; good tests, except that two compare floats with `==` against
# literals (the checker warns whether or not they happen to pass).
using BayesReg, Test, LinearAlgebra

@testset "posterior" begin
    X = [1.0 -1.0; 1.0 0.0; 1.0 1.0]      # orthogonal columns: A is diagonal
    y = [0.2, 1.1, 1.9]
    s, t = 0.5, 2.0
    post = posterior_exact(X, y; sigma = s, tau = t)
    A = X' * X / s^2 + I / t^2
    @test post.mean ≈ A \ (X' * y / s^2) rtol = 1e-12     # cond(A) < 2: a few eps
    @test post.cov ≈ inv(A) rtol = 1e-12
    @test post.cov[1, 2] == 0.0
    @test posterior_exact(X, y; sigma = s, tau = 1e6).mean[2] == 0.85
    @test_throws ArgumentError posterior_exact(X, y; sigma = -s, tau = t)
end
