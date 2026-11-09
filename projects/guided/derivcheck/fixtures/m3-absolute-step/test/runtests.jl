using DerivCheck, Test

f(v) = v[1]^3 * v[2] + exp(v[2])
df(v) = [3v[1]^2 * v[2], v[1]^3 + exp(v[2])]
pts = ([1.0, 0.5], [-2.0, 1.5])

@testset "symbolic" begin
    G = symbolic_gradient(f, 2)
    for x in pts
        @test G(x) isa Vector{Float64}
        @test isapprox(G(x), df(x); rtol = 1e-12)   # same formula, other operation order: a few eps
    end
    @test_throws ArgumentError symbolic_gradient(f, 0)
end

@testset "ad" begin
    for x in pts
        @test isapprox(ad_gradient(f, x), df(x); rtol = 1e-13)   # exact up to rounding
    end
    J = ad_jacobian(v -> [v[1] * v[2], v[2], 2v[1]], [3.0, 4.0])
    @test size(J) == (3, 2)
    @test isapprox(J, [4.0 3.0; 0.0 1.0; 2.0 0.0]; rtol = 1e-13)
end

@testset "central differences" begin
    for x in pts
        @test isapprox(central_difference(f, x), df(x); rtol = 1e-8)   # error ~ eps^(2/3)
    end
    x = [5.0e5, 2.0]
    xs = copy(x)
    @test isapprox(central_difference(v -> v[1]^3, x), [3 * 5.0e5^2, 0.0]; rtol = 1e-8)
    @test x == xs
    @test isapprox(central_difference(v -> v[1]^3, [1.0]; h = 0.1), [3.01]; rtol = 1e-12)   # exactly 3 + s^2
    @test isapprox(central_difference(v -> v[1]^2, [1, 2]), [2.0, 0.0]; rtol = 1e-8)
end
