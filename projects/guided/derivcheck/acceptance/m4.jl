# Acceptance, milestone 4: GradientReport and check_gradient. One @testset per behaviour id.
#
# The relative errors compared here are either exactly 0 (a correct gradient
# is the same formula as AD, up to a few eps), or 1e-3 or more (a deliberate
# error), so rtol = 1e-8 separates them by orders of magnitude.
using DerivCheck, Test

f(v) = v[1]^2 + 3v[2]
g_right(v) = [2v[1], 3.0]
g_wrong(v) = [2v[1] + (v[1] > 1.5 ? 0.1 : 0.0), 3.0]      # wrong only beyond 1.5

const PTS = [[0.0, 0.0], [1.0, 1.0], [2.0, 0.5], [1.6, -1.0]]

@testset "report-fields" begin
    r = check_gradient(f, g_right, PTS)
    @test r isa GradientReport
    @test fieldnames(GradientReport) == (:ok, :worst_point, :worst_error)
    @test all(isconcretetype, fieldtypes(GradientReport))
    @test r.ok isa Bool
    @test r.worst_point isa Vector{Float64}
    @test r.worst_error isa Float64
end

@testset "agreement" begin
    r = check_gradient(f, g_right, PTS)
    @test r.ok
    @test r.worst_error <= 1e-12
    @test check_gradient(f, g_wrong, PTS; rtol = 1e-8).ok == false
    # The threshold is rtol: the worst error, ~0.0228, passes with rtol = 0.05.
    @test check_gradient(f, g_wrong, PTS; rtol = 0.05).ok
end

@testset "worst-point" begin
    # Relative errors: at [2.0, 0.5] |0.1| / |(4, 3)| = 0.02; at [1.6, -1.0] 0.1 / |(3.2, 3)| ≈ 0.0228.
    r = check_gradient(f, g_wrong, PTS)
    @test r.worst_point == PTS[4]   # exact on purpose: one of the given points, not a computed one
    @test isapprox(r.worst_error, 0.1 / sqrt(3.2^2 + 9); rtol = 1e-12)
end

@testset "relative-floor" begin
    # A zero gradient: the error is measured absolutely there, so a correct
    # gradient passes and an off-by-1e-3 one does not.
    h(v) = (v[1] - 1)^2
    @test check_gradient(h, v -> [2 * (v[1] - 1)], [[1.0]]).ok
    r = check_gradient(h, v -> [2 * (v[1] - 1) + 1e-3], [[1.0]])
    @test !r.ok
    @test isapprox(r.worst_error, 1e-3; rtol = 1e-9)
end

@testset "nan-fails" begin
    r = check_gradient(f, v -> [NaN, 3.0], PTS)
    @test !r.ok
    @test check_gradient(f, v -> v[1] > 1.5 ? [NaN, 3.0] : g_right(v), PTS).ok == false
end

@testset "empty-points" begin
    @test_throws ArgumentError check_gradient(f, g_right, Vector{Float64}[])
end
