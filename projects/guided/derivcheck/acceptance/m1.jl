# Acceptance, milestone 1: symbolic_gradient. One @testset per behaviour id.
#
# Tolerance: the compiled symbolic gradient and the hand-written formula below
# evaluate the same expression with operations in a possibly different order.
# Each component is a handful of correctly rounded operations (exp, sin, cos
# are within 1 ulp) on values of size 1 to 30 with no cancellation at these
# points, so the difference is a few eps relative; rtol = 1e-12 leaves a
# margin of ~4500 eps and rejects any wrong derivative.
using DerivCheck, Test

const RTOL = 1e-12

f1(v) = v[1]^2 * sin(v[2]) + exp(v[1])
g1(v) = [2v[1] * sin(v[2]) + exp(v[1]), v[1]^2 * cos(v[2])]
f2(v) = v[1] * v[2] * v[3] + v[3]^3
g2(v) = [v[2] * v[3], v[1] * v[3], v[1] * v[2] + 3v[3]^2]

@testset "sym-values" begin
    G1 = symbolic_gradient(f1, 2)
    for x in ([1.0, 2.0], [0.5, 1.0], [2.0, 0.3])
        @test isapprox(G1(x), g1(x); rtol = RTOL)
    end
    G2 = symbolic_gradient(f2, 3)
    for x in ([1.0, 2.0, 3.0], [3.0, 0.5, 1.5])
        @test isapprox(G2(x), g2(x); rtol = RTOL)
    end
    G0 = symbolic_gradient(v -> 3v[1] + 4, 1)
    @test isapprox(G0([10.0]), [3.0]; rtol = RTOL)
end

@testset "sym-returns-vector" begin
    G = symbolic_gradient(f2, 3)
    r = G([1.0, 2.0, 3.0])
    @test r isa Vector{Float64}
    @test length(r) == 3
    @test isapprox(G([3.0, 0.5, 1.5]), g2([3.0, 0.5, 1.5]); rtol = RTOL)   # callable again
end

@testset "sym-n-check" begin
    @test_throws ArgumentError symbolic_gradient(f1, 0)
    @test_throws ArgumentError symbolic_gradient(f1, -1)
end
