# Exemplary student tests, milestone 4: check_gradient.

@testset "check_gradient" begin
    f(v) = 2v[1]^2 + v[2]
    good(v) = [4v[1], 1.0]
    bad(v) = [4v[1] + (v[1] > 0 ? 0.5 : 0.0), 1.0]
    pts = [[-1.0, 0.0], [0.5, 2.0], [0.25, 1.0]]
    r = check_gradient(f, good, pts)
    @test r.ok
    @test all(isconcretetype, fieldtypes(GradientReport))
    b = check_gradient(f, bad, pts)
    @test !b.ok
    # errors: 0, 0.5/|(2,1)| ≈ 0.224, 0.5/|(1,1)| ≈ 0.354: the last point is the worst
    @test b.worst_point == pts[end]   # exact on purpose: the point itself is returned
    @test b.worst_error ≈ 0.5 / sqrt(2) rtol = 1e-12
    @test check_gradient(f, bad, pts; rtol = 0.5).ok
    # A zero gradient is compared absolutely; NaN never passes; no points is an error.
    @test check_gradient(v -> v[1]^2, v -> [2v[1]], [[0.0]]).ok
    @test !check_gradient(f, v -> [NaN, 1.0], pts).ok
    @test_throws ArgumentError check_gradient(f, good, Vector{Float64}[])
end
