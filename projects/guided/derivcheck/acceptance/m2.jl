# Acceptance, milestone 2: ad_gradient and ad_jacobian. One @testset per behaviour id.
#
# Tolerance: forward-mode AD evaluates the derivative formula with dual
# numbers, so it is exact up to rounding in the same few operations as the
# hand-written formula: rtol = 1e-13 (~450 eps). A finite-difference
# approximation is off by ~1e-10 or more here, so it fails this bound.
using DerivCheck, Test

const RTOL = 1e-13

f(v) = v[1]^3 * v[2] + exp(v[2])
g(v) = [3v[1]^2 * v[2], v[1]^3 + exp(v[2])]
F(v) = [v[1] * v[2], v[1] + 2v[2] + 3v[3]]          # R^3 -> R^2
J(v) = [v[2] v[1] 0.0; 1.0 2.0 3.0]
S(v) = [v[1]^2, v[1] * v[2]]                         # square, not symmetric
JS(v) = [2v[1] 0.0; v[2] v[1]]

@testset "ad-gradient" begin
    for x in ([1.3, 0.7], [2.0, -1.0], [-0.5, 2.5])
        @test isapprox(ad_gradient(f, x), g(x); rtol = RTOL)
    end
end

@testset "ad-jacobian" begin
    x = [1.5, 2.0, -1.0]
    Jx = ad_jacobian(F, x)
    @test size(Jx) == (2, 3)
    @test isapprox(Jx, J(x); rtol = RTOL)
    y = [3.0, 5.0]
    @test isapprox(ad_jacobian(S, y), JS(y); rtol = RTOL)
end
