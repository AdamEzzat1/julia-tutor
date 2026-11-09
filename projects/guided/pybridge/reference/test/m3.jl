# Exemplary student tests, milestone 3: two moving averages.
using Random

@testset "moving averages by hand" begin
    # Means of halves and quarters are exact in binary: `isequal` is right.
    @test isequal(moving_average([1.0, 2.0, 3.0, 4.0], 2), [1.5, 2.5, 3.5])
    @test isequal(moving_average([1.0, 2.0, 3.0, 4.0], 1), [1.0, 2.0, 3.0, 4.0])
    @test isequal(moving_average([1.0, 2.0, 3.0, 6.0], 4), [3.0])
    r = moving_average_np([1.0, 2.0, 3.0, 4.0], 2)
    @test length(r) == 3
    @test isapprox(r, [1.5, 2.5, 3.5]; rtol = 4eps())    # a 2-term product sum: a few eps at most
end

@testset "NumPy and Julia agree" begin
    v = rand(Xoshiro(1), 10^5) .* 100
    n, k = length(v), 50
    a = moving_average(v, k)
    b = moving_average_np(v, k)
    @test a isa Vector{Float64}
    # n running-sum updates, each off by up to eps · k · max|v|, divided by k;
    # plus k roundings per convolve output: (n + k) · eps · max|v| bounds the gap.
    @test maximum(abs, a .- b) <= (n + k) * eps() * maximum(abs, v)
end

@testset "bad windows" begin
    @test_throws ArgumentError moving_average([1.0, 2.0], 0)
    @test_throws ArgumentError moving_average([1.0, 2.0], 3)
    @test_throws ArgumentError moving_average_np([1.0, 2.0], 0)
end
