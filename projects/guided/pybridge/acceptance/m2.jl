# Acceptance, milestone 2: matrices keep their indices across the boundary. One @testset per behaviour id.
# Values are written by the test and read back unchanged, so exact `isequal` is right.
using PyBridge, PythonCall, Test

const np = pyimport("numpy")
getf(a, i...) = pyconvert(Float64, a[i...])

@testset "matrix-layout" begin
    A = [1.0 2.0 3.0; 4.0 5.0 6.0]                     # 2 × 3: a swap shows in the shape
    a = as_numpy(A)
    @test pyconvert(Tuple{Int,Int}, a.shape) == (2, 3)
    @test all(isequal(getf(a, i - 1, j - 1), A[i, j]) for i in 1:2, j in 1:3)
    B = reshape(collect(1.0:12.0), 3, 4)
    b = as_numpy(B)
    @test pyconvert(Tuple{Int,Int}, b.shape) == (3, 4)
    @test all(isequal(getf(b, i - 1, j - 1), B[i, j]) for i in 1:3, j in 1:4)
end

@testset "matrix-shares" begin
    A = [1.0 2.0 3.0; 4.0 5.0 6.0]
    a = as_numpy(A)
    @test pyconvert(Bool, a.flags.f_contiguous)
    a[1, 2] = 9.5
    @test isequal(A[2, 3], 9.5)
    A[1, 2] = -1.0
    @test isequal(getf(a, 0, 1), -1.0)
end

@testset "matrix-copy" begin
    c = np.arange(6.0).reshape(2, 3)                   # C order: rows contiguous
    M = from_numpy(c)
    @test M isa Matrix{Float64}
    @test size(M) == (2, 3)
    @test isequal(M, [0.0 1.0 2.0; 3.0 4.0 5.0])
    f = np.asfortranarray(np.arange(6.0).reshape(3, 2))
    @test isequal(from_numpy(f), [0.0 1.0; 2.0 3.0; 4.0 5.0])
    M[1, 1] = 42.0
    @test isequal(getf(c, 0, 0), 0.0)
end
