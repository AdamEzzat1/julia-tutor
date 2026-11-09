# Acceptance, milestone 3: central_difference. One @testset per behaviour id.
#
# Error model for the central difference with step s = h * max(1, |x_i|):
#   truncation  s^2 |f'''| / 6      (next term of the Taylor expansion)
#   rounding    ~ eps |f| / s       (two evaluations, each off by ~eps |f|/2)
# With h = cbrt(eps) ≈ 6.06e-6 both are ~eps^(2/3) ≈ 3.7e-11 times the scale
# of f, so for the well-scaled functions below the relative error is a few
# 1e-11; RTOL = 1e-8 is a 100x margin. The step-scaling test is chosen so a
# step that ignores |x_i| has rounding error 2e-5 to 8e-5 relative: over 1000x RTOL.
using DerivCheck, Test

const RTOL = 1e-8

@testset "fd-accuracy" begin
    f(v) = sin(v[1]) * exp(v[2]) + v[1] * v[2]^2
    g(v) = [cos(v[1]) * exp(v[2]) + v[2]^2, sin(v[1]) * exp(v[2]) + 2v[1] * v[2]]
    for x in ([0.3, 0.8], [1.2, -0.4], [2.0, 0.1])
        @test isapprox(central_difference(f, x), g(x); rtol = RTOL)
    end
    @test central_difference(f, [0.3, 0.8]) isa Vector{Float64}
end

@testset "fd-relative-step" begin
    # f = x1^3 + x2^3 at x = (1e6, -2e6): |f| ≈ 7e18, f'_1 = 3e12, f'_2 = 1.2e13.
    # Relative step s_1 = 6.06: truncation s^2 ≈ 37, rounding 2.2e-16 * 7e18 / 6 ≈ 260:
    #   ~1e-10 of 3e12 (component 2 is smaller still).
    # Absolute step s = 6.06e-6: rounding 2.2e-16 * 7e18 / 6.06e-6 ≈ 2.5e8, i.e. ~8e-5 of 3e12.
    f(v) = v[1]^3 + v[2]^3
    x = [1.0e6, -2.0e6]
    @test isapprox(central_difference(f, x), [3 * x[1]^2, 3 * x[2]^2]; rtol = RTOL)
end

@testset "fd-step-keyword" begin
    # For a cubic the central difference is exact up to rounding apart from
    # the term s^2 * f''' / 6 = s^2: with h = 0.01 at x = 1, 3 + 1e-4 exactly.
    f(v) = v[1]^3
    @test isapprox(central_difference(f, [1.0]; h = 0.01), [3.0001]; rtol = 1e-10)
    # And the step is relative: at x = 100, s = 1 and the result is 3e4 + 1.
    @test isapprox(central_difference(f, [100.0]; h = 0.01), [30001.0]; rtol = 1e-10)
end

@testset "fd-no-mutation" begin
    f(v) = sum(abs2, v)
    x = [1.0, 2.0, 3.0]
    x0 = copy(x)
    central_difference(f, x)
    @test isequal(x, x0)   # exact on purpose: the input must be untouched, bit for bit
    # Integer input works too (and is not changed).
    xi = [1, 2]
    @test isapprox(central_difference(f, xi), [2.0, 4.0]; rtol = RTOL)
    @test xi == [1, 2]
end
