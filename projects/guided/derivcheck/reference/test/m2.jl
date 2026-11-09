# Exemplary student tests, milestone 2: forward-mode AD.
# AD is exact up to rounding: rtol = 1e-13. A finite-difference stand-in is
# off by ~1e-10 here and fails.

@testset "forward-mode AD" begin
    f(v) = exp(v[1]) * v[2]^2
    @test ad_gradient(f, [0.5, 3.0]) ≈ [exp(0.5) * 9, 2 * exp(0.5) * 3] rtol = 1e-13
    F(v) = [v[1] + v[2], v[1] * v[3]]                 # 2 outputs, 3 inputs
    J = ad_jacobian(F, [2.0, 3.0, 5.0])
    @test size(J) == (2, 3)
    @test J ≈ [1.0 1.0 0.0; 5.0 0.0 2.0] rtol = 1e-13
end
