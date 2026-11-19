# Hidden acceptance tests, milestone 2 (stage 2 adds: gradient,
# central_diff, fit_order). Other functions than the visible tests; every
# tolerance derived in a comment; nothing is random.

using Test
using DualAD

const EPS = eps(Float64)

@testset "gradient-each-component-seeded" begin
    # Exact: integer-valued polynomial terms at integer points. The
    # components differ, so a seed on the wrong component or on all of them
    # at once is visible.
    r(x) = x[1]^2 * x[2] - 3 * x[2] * x[3] + x[4]
    @test isequal(gradient(r, [1.0, 2.0, 3.0, 4.0]), [4.0, -8.0, -6.0, 1.0])
    @test isequal(gradient(r, [2, 0, 1, -1]), [0.0, 1.0, 0.0, 1.0])
    # One evaluation per component, on duals.
    seen = Type[]
    gradient(x -> (push!(seen, eltype(x)); x[1] + x[2] + x[3]), [1.0, 2.0, 3.0])
    @test length(seen) == 3 && all(T -> T <: Dual, seen)
    # Rounding level on a non-polynomial (8 eps: three roundings and a product).
    gr = gradient(x -> exp(x[1]) * cos(x[2]), [0.5, 1.5])
    @test isapprox(gr[1], exp(0.5) * cos(1.5); rtol = 8EPS)
    @test isapprox(gr[2], -exp(0.5) * sin(1.5); rtol = 8EPS)
    @test eltype(gradient(r, [1, 2, 3, 4])) == Float64
end

@testset "central-difference-symmetric" begin
    # On x^3 the central difference is 3x^2 + h^2 exactly (truncation
    # h^2 f'''/6 = h^2), and with dyadic x and h Float64 computes it exactly.
    # That pins
    # both the symmetric form and the factor 2.
    @test isequal(central_diff(x -> x^3, 1.0, 0.5), 3.25)
    @test isequal(central_diff(x -> x^3, 2.0, 0.25), 12.0625)
    # Order 2 on exp at x = 0.3 over h = 2^-2 .. 2^-7 (truncation >= 1e-6
    # relative there, rounding <= 1e-13): window 2 +- 0.1, which excludes the
    # forward difference's order 1.
    hs = [2.0^-k for k in 2:7]
    errs = [abs(central_diff(exp, 0.3, h) / exp(0.3) - 1) for h in hs]
    @test 1.9 <= fit_order(hs, errs) <= 2.1
end

@testset "order-fit-least-squares" begin
    # The least-squares slope, recomputed here; points not on a line, so the
    # end-point slope differs by more than 1%.
    hs = [0.5, 0.2, 0.05, 0.01]
    errs = [0.3, 0.02, 0.01, 1e-5]
    x, y = log.(hs), log.(errs)
    xm, ym = sum(x) / 4, sum(y) / 4
    ls = sum((x .- xm) .* (y .- ym)) / sum(abs2, x .- xm)
    @test isapprox(fit_order(hs, errs), ls; rtol = 1e-12)
    @test !isapprox(fit_order(hs, errs), (y[4] - y[1]) / (x[4] - x[1]); rtol = 0.01)
    # A rounding-dominated curve C / h has slope -1 (exact data: 1e-12 relative).
    @test isapprox(fit_order([1e-8, 1e-9, 1e-10], [1e-8, 1e-7, 1e-6]), -1; rtol = 1e-12)
    @test_throws ArgumentError fit_order([0.1, 0.2], [1.0, -1.0])
end
