# Exemplary student tests, milestone 3: central differences.
# With the default step the error is ~eps^(2/3) ≈ 4e-11 relative for these
# well-scaled functions; rtol = 1e-8 is a wide margin.

@testset "central_difference" begin
    f(v) = cos(v[1]) + v[1] * v[2]
    x = [0.7, 1.9]
    x0 = copy(x)
    @test central_difference(f, x) ≈ [-sin(0.7) + 1.9, 0.7] rtol = 1e-8
    @test isequal(x, x0)                             # input unchanged (exact on purpose)
    # Large |x|: the step must scale with x (an absolute step loses ~1e-5 here).
    c(v) = v[1]^3
    @test central_difference(c, [1.0e6]) ≈ [3.0e12] rtol = 1e-8
    # For a cubic the result is exactly 3x^2 + s^2 with s = h * max(1, |x|).
    @test central_difference(c, [2.0]; h = 0.1) ≈ [12.0 + 0.2^2] rtol = 1e-12
end
