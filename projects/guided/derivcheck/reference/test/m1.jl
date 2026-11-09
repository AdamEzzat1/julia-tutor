# Exemplary student tests, milestone 1: symbolic_gradient.
# rtol = 1e-12: the compiled gradient and my formula differ only in the order
# of a few rounded operations on values of size ~1 (a few eps).

@testset "symbolic_gradient" begin
    f(v) = v[1]^2 * v[2] + sin(v[2])
    df(v) = [2v[1] * v[2], v[1]^2 + cos(v[2])]
    G = symbolic_gradient(f, 2)
    for x in ([1.0, 2.0], [-0.5, 0.25])
        r = G(x)
        @test r isa Vector{Float64}
        @test r ≈ df(x) rtol = 1e-12
    end
    @test_throws ArgumentError symbolic_gradient(f, 0)
end
