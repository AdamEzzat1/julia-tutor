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
