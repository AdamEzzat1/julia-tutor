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
