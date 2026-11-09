using PyBridge, Test

# Exemplary student tests, milestone 0 (included from a runtests.jl that does `using PyBridge, Test`).
@testset "the package loads" begin
    @test PyBridge isa Module
end

# Exemplary student tests, milestone 1: copies and views.
# Every value is one the test wrote, so `isequal` compares exactly.
using PythonCall, Random

np = pyimport("numpy")

@testset "a view shares memory" begin
    v = [1.0, 2.0, 3.0]
    a = as_numpy(v)
    a[0] = 10.0                          # Python index 0 is v[1]
    @test isequal(v[1], 10.0)
    v[2] = 20.0
    @test isequal(pyconvert(Float64, a[1]), 20.0)
end

@testset "a copy is independent" begin
    a = np.arange(1.0, 4.0)
    c = from_numpy(a)
    @test c isa Vector{Float64}
    @test isequal(c, [1.0, 2.0, 3.0])
    c[1] = -1.0
    @test isequal(pyconvert(Float64, a[0]), 1.0)
    a[2] = 30.0
    @test isequal(c[3], 3.0)
    @test isequal(from_numpy(np.arange(3)), [0.0, 1.0, 2.0])
    @test from_numpy(np.arange(3)) isa Vector{Float64}
end

# Exemplary student tests, milestone 2: layout. A 2 × 3 matrix, so a swap of
# rows and columns cannot go unnoticed.
using PythonCall

@testset "matrix to NumPy" begin
    np = pyimport("numpy")
    A = [1.0 2.0 3.0; 4.0 5.0 6.0]
    a = as_numpy(A)
    @test pyconvert(Tuple, a.shape) == (2, 3)
    for i in 1:2, j in 1:3
        @test isequal(pyconvert(Float64, a[i-1, j-1]), A[i, j])
    end
    @test pyconvert(Bool, a.flags.f_contiguous)
    a[0, 2] = 30.0
    @test isequal(A[1, 3], 30.0)
end

@testset "matrix from NumPy" begin
    np = pyimport("numpy")
    c = np.arange(6.0).reshape(2, 3)     # row-major on the NumPy side
    M = from_numpy(c)
    @test M isa Matrix{Float64}
    @test isequal(M, [0.0 1.0 2.0; 3.0 4.0 5.0])
end

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

