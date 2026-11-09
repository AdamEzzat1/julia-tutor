# Correct code; tests that check only shapes and the properties of a covariance,
# with sigma = tau = 1, so no scaling mistake can show.
using BayesReg, Test, LinearAlgebra

@testset "posterior" begin
    X = [1.0 0.0; 1.0 1.0; 1.0 2.0]
    y = [0.5, 1.4, 2.6]
    post = posterior_exact(X, y; sigma = 1.0, tau = 1.0)
    @test length(post.mean) == 2
    @test size(post.cov) == (2, 2)
    @test issymmetric(post.cov)
    @test isposdef(post.cov)
end
