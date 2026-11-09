# Acceptance, milestone 3: two moving averages. One @testset per behaviour id.
#
# Small cases use values whose window means are exact in binary (sums of a
# few halves and quarters, divided by a power of two or computed exactly), so
# `isequal` is right there. On random data the tolerance is derived:
# the running sum makes n updates, each rounding by at most eps times a
# partial sum no larger than k · max|v|; dividing by k, a mean is off by at
# most n · eps · max|v|, and convolve's k-term sums add k · eps · max|v|.
# Bound: (n + k) · eps · max|v|. Observed on seed 7: about 1e-12 against 2e-9.
using PyBridge, Random, Test

@testset "ma-values" begin
    @test isequal(moving_average([1.0, 2.0, 3.0, 4.0], 2), [1.5, 2.5, 3.5])
    @test isequal(moving_average([1.0, 3.0, 5.0, 7.0, 9.0], 4), [4.0, 6.0])
    @test isequal(moving_average([0.5, -1.5, 2.25, 4.0], 1), [0.5, -1.5, 2.25, 4.0])
    @test isequal(moving_average([0.5, -1.5, 2.25, 4.75], 4), [1.5])
    @test isequal(moving_average([2, 4, 6], 2), [3.0, 5.0])      # integer input
end

@testset "ma-numpy" begin
    r = moving_average_np([1.0, 2.0, 3.0, 4.0], 2)
    @test length(r) == 3
    @test isapprox(r, [1.5, 2.5, 3.5]; rtol = 4eps())             # k products and sums of exact halves
    @test isapprox(moving_average_np([1.0, 3.0, 5.0, 7.0, 9.0], 4), [4.0, 6.0]; rtol = 8eps())
    @test length(moving_average_np(collect(1.0:10.0), 10)) == 1
end

@testset "ma-agree" begin
    v = rand(Xoshiro(7), 10^5) .* 100
    n, k = length(v), 50
    a = moving_average(v, k); b = moving_average_np(v, k)
    @test a isa Vector{Float64}
    @test b isa Vector{Float64}
    @test length(a) == length(b) == n - k + 1
    @test maximum(abs, a .- b) <= (n + k) * eps() * maximum(abs, v)
end

@testset "ma-window" begin
    v = [1.0, 2.0, 3.0]
    @test_throws ArgumentError moving_average(v, 0)
    @test_throws ArgumentError moving_average(v, 4)
    @test_throws ArgumentError moving_average_np(v, 0)
    @test_throws ArgumentError moving_average_np(v, 4)
end
