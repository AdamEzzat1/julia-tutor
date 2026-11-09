# Acceptance, milestone 1: views share memory, copies do not. One @testset per behaviour id.
# Values are written by the test and read back unchanged, so exact `isequal` is right.
using PyBridge, PythonCall, Test

const np = pyimport("numpy")
getf(a, i...) = pyconvert(Float64, a[i...])

@testset "view-shares" begin
    v = [1.0, 2.0, 3.0, 4.0]
    a = as_numpy(v)
    a[0] = 7.5
    @test isequal(v[1], 7.5)
    v[3] = -2.25
    @test isequal(getf(a, 2), -2.25)
    @test pyconvert(Int, a.size) == 4
end

@testset "copy-independent" begin
    a = np.arange(1.0, 5.0)              # 1, 2, 3, 4 as float64
    c = from_numpy(a)
    @test c isa Vector{Float64}
    @test isequal(c, [1.0, 2.0, 3.0, 4.0])
    c[1] = 100.0
    @test isequal(getf(a, 0), 1.0)
    a[1] = 50.0
    @test isequal(c[2], 2.0)
end

@testset "copy-converts" begin
    c = from_numpy(np.arange(4))         # int64 on the NumPy side
    @test c isa Vector{Float64}
    @test isequal(c, [0.0, 1.0, 2.0, 3.0])
end
