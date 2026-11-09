using DerivCheck, Test

@testset "check_gradient" begin
    f(v) = v[1]^2
    r = check_gradient(f, v -> [2v[1]], [[1.0], [2.0]])
    @test r.ok
    @test !check_gradient(f, v -> [2v[1] + 1], [[1.0], [2.0]]).ok
end
