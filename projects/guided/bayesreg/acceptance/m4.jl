# Acceptance, milestone 4: predictive_interval. One @testset per behaviour id.
#
# Exact method: the interval is a handful of rounded operations on O(1)
# numbers plus a normal quantile (StatsFuns' norminvcdf, accurate to a few
# eps); every end tested lies between -1 and 10 and at least 0.2 from zero,
# so there is no cancellation to amplify it, and RTOL = 1e-12 is about 4500
# eps of slack and far below any modelling mistake (dropping the
# noise or taking a one-sided quantile moves an end by more than 0.1).
#
# Draws method: see SE below; no sampler involved, the draws are independent.
using BayesReg, Test, LinearAlgebra, Random, Statistics
using Turing: MvNormal, Normal, quantile

const X = hcat(ones(20), collect(range(-1, 1; length = 20)))
const Y = X * [1.0, 2.0] .+ 0.5 .* randn(Xoshiro(11), 20)   # fixed seed
const SIGMA = 0.5
const POST = posterior_exact(X, Y; sigma = SIGMA, tau = 2.0)
const XNEW = [1.0, 3.0]    # extrapolating: coefficient variance 0.31 vs noise variance 0.25
const RTOL = 1e-12

function hand_interval(x, level)
    mu = dot(x, POST.mean)
    s = sqrt(dot(x, POST.cov * x) + SIGMA^2)
    z = quantile(Normal(), (1 + level) / 2)
    return (mu - z * s, mu + z * s)
end

@testset "predictive-exact" begin
    for x in (XNEW, [1.0, 0.0], [1.0, -0.5])
        iv = predictive_interval(POST, x; sigma = SIGMA)
        @test iv isa Tuple{Float64,Float64}
        h = hand_interval(x, 0.9)
        @test isapprox(iv[1], h[1]; rtol = RTOL)
        @test isapprox(iv[2], h[2]; rtol = RTOL)
    end
end

@testset "predictive-level" begin
    for level in (0.5, 0.99)
        iv = predictive_interval(POST, XNEW; sigma = SIGMA, level = level)
        h = hand_interval(XNEW, level)
        @test isapprox(iv[1], h[1]; rtol = RTOL)
        @test isapprox(iv[2], h[2]; rtol = RTOL)
    end
    w90 = -(reverse(predictive_interval(POST, XNEW; sigma = SIGMA))...)
    w99 = -(reverse(predictive_interval(POST, XNEW; sigma = SIGMA, level = 0.99))...)
    @test w99 > w90
    D = [1.0 2.0; 1.5 2.5; 0.5 1.5]
    for bad in (0.0, 1.0, 1.5, -0.1)
        @test_throws ArgumentError predictive_interval(POST, XNEW; sigma = SIGMA, level = bad)
        @test_throws ArgumentError predictive_interval(D, XNEW; sigma = SIGMA, level = bad)
    end
end

@testset "predictive-samples" begin
    n = 4000
    D = permutedims(rand(Xoshiro(21), MvNormal(POST.mean, POST.cov), n))   # n × 2, independent
    for (x, level) in ((XNEW, 0.9), ([1.0, 0.0], 0.9), (XNEW, 0.5))
        iv = predictive_interval(D, x; sigma = SIGMA, level = level)
        h = hand_interval(x, level)
        # SE of an end mu_hat ± z sqrt(v_hat + sigma^2), v = Var(x'w): the mean
        # has variance v / n, the sample variance about 2 v^2 / (n - 1) for
        # normal draws (independent of the mean), and the square root's
        # derivative is 1 / (2 sqrt(v + sigma^2)). 5 SE fails with probability
        # about 5.7e-7 per end for a correct method.
        v = dot(x, POST.cov * x)
        z = quantile(Normal(), (1 + level) / 2)
        se = sqrt(v / n + z^2 * 2v^2 / (n - 1) / (4 * (v + SIGMA^2)))
        @test abs(iv[1] - h[1]) <= 5se
        @test abs(iv[2] - h[2]) <= 5se
    end
end
