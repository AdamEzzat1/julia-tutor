using PyBridge, PythonCall, Test

# Expects the copy to follow later changes to the NumPy array, which the spec rules out.
@testset "from_numpy" begin
    np = pyimport("numpy")
    a = np.arange(1.0, 4.0)
    c = from_numpy(a)
    a[0] = 9.0
    @test isequal(c[1], 9.0)
    v = [1.0, 2.0]
    as_numpy(v)[0] = 5.0
    @test isequal(v[1], 5.0)
end
