# Hidden acceptance tests, milestone 1 (stage-1 holes: rhs, jacobian,
# solve_pivot, bs32_step). Other rate constants, points, systems and
# problems than the visible tests, so code fitted to those does not pass by
# accident. Every tolerance is derived in a comment; nothing is random.

using Test
using StiffKin

const EPS = eps(Float64)

@testset "rate-equations-other-constants" begin
    # k = (2, 5, 7) at y = (0.2, 0.3, 0.5): a = 0.4, b = 7 * 0.3 * 0.5 = 1.05,
    # c = 5 * 0.09 = 0.45. A few roundings each: 8 eps relative.
    @test isapprox(rhs([0.2, 0.3, 0.5], Kinetics(2.0, 5.0, 7.0)), [0.65, -1.1, 0.45]; rtol = 8EPS)
    # No B: only A -> B runs, whatever k2 and k3 are (exact).
    @test isequal(rhs([0.6, 0.0, 0.4], Kinetics(0.5, 9.0, 9.0)), [-0.3, 0.3, 0.0])
    # Only B: B + B -> C + B runs (exact: 4 * 0.25 = 1).
    @test isequal(rhs([0.0, 0.5, 0.0], Kinetics(1.0, 4.0, 1.0)), [0.0, -1.0, 1.0])
end

@testset "jacobian-matches-differences-and-conserves" begin
    # As in the visible test: rhs is quadratic, so central differences are
    # exact up to rounding, eps |f| / h ~ 2e-16 * 50 / 1e-7 = 1e-7 here
    # (|f| up to 50, entries up to 2e3): tolerance 1e-5.
    p = Kinetics(0.5, 1e3, 50.0)
    y = [0.1, 1e-3, 0.9]
    J = jacobian(y, p)
    h = 1e-7
    for j in 1:3
        e = zeros(3)
        e[j] = h
        @test isapprox(J[:, j], (rhs(y .+ e, p) .- rhs(y .- e, p)) ./ (2h); atol = 1e-5)
    end
    # The transpose would have zero row sums instead: a direction where only
    # y2 moves changes all three rates.
    @test all(j -> abs(sum(J[:, j])) <= 8EPS * maximum(abs, J), 1:3)
    @test !isapprox(J, permutedims(J); rtol = 1e-3)
end

@testset "pivoted-solve-larger-system" begin
    # A 4x4 system with a zero and a tiny leading entry in turn. With partial
    # pivoting the error is at most cond * n * growth * eps; cond < 50 (computed
    # when authoring), n = 4, growth <= 8: 1e-12 is generous. Without the
    # pivot the 1e-18 entry gives O(1) errors.
    A = [1e-18 2.0 -1.0 0.5
         1.0 1.0 0.0 2.0
         2.0 -1.0 3.0 0.0
         -1.0 0.5 1.0 4.0]
    xt = [1.5, -0.5, 2.0, 0.25]
    b = A * xt
    @test isapprox(solve_pivot(A, b), xt; rtol = 1e-12)
    # A permutation matrix: pivoting alone solves it, exactly.
    P = [0.0 0.0 1.0; 1.0 0.0 0.0; 0.0 1.0 0.0]
    @test isequal(solve_pivot(P, [3.0, 1.0, 2.0]), [1.0, 2.0, 3.0])
    # Integer input is converted, not truncated.
    @test isapprox(solve_pivot([2 1; 1 3], [1, 2]), [0.2, 0.6]; rtol = 4EPS)
    @test_throws ArgumentError solve_pivot(zeros(3, 3), ones(3))
end

@testset "bs32-nonlinear-local-order" begin
    # y' = -y^2 from y = 1 has y(h) = 1 / (1 + h). Halving h divides the
    # local error of ynew by 16 and the estimate by 8 (leading terms; under
    # 10% from the next ones at h = 0.02, 0.01).
    f(y) = -(y .^ 2)
    loc(h) = abs(bs32_step(f, [1.0], h)[1][1] - 1 / (1 + h))
    est(h) = abs(bs32_step(f, [1.0], h)[2][1])
    @test 14 <= loc(0.02) / loc(0.01) <= 18
    @test 7 <= est(0.02) / est(0.01) <= 9
    # Componentwise on a system, and the input is not modified.
    y = [1.0, 2.0]
    ynew, err, nf = bs32_step(u -> [u[2], -u[1]], y, 0.1)
    @test isequal(y, [1.0, 2.0]) && nf == 4 && length(err) == 2
    @test isapprox(ynew, [cos(0.1) + 2sin(0.1), 2cos(0.1) - sin(0.1)]; atol = 1e-5)
end
