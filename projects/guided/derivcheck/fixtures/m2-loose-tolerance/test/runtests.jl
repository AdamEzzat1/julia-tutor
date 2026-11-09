# Correct code; the AD test uses a tolerance a finite-difference stand-in also meets.
using DerivCheck, Test

f(v) = v[1]^3 * v[2] + exp(v[2])
df(v) = [3v[1]^2 * v[2], v[1]^3 + exp(v[2])]

@testset "symbolic" begin
    G = symbolic_gradient(f, 2)
    @test G([1.0, 0.5]) isa Vector{Float64}
    @test isapprox(G([1.0, 0.5]), df([1.0, 0.5]); rtol = 1e-12)
    @test_throws ArgumentError symbolic_gradient(f, 0)
end

@testset "ad" begin
    @test isapprox(ad_gradient(f, [1.0, 0.5]), df([1.0, 0.5]); rtol = 1e-4)
    J = ad_jacobian(v -> [v[1] * v[2], v[2], 2v[1]], [3.0, 4.0])
    @test size(J) == (3, 2)
    @test isapprox(J, [4.0 3.0; 0.0 1.0; 2.0 0.0]; rtol = 1e-4)
end
