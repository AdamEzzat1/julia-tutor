# Hidden acceptance tests, milestone 1 (stage-1 holes: second_difference,
# ftcs_step, thomas, mms_problem). Other grids, profiles and systems than
# the visible tests, so code fitted to those does not pass by accident.
# Every tolerance is derived in a comment; nothing is random.

using Test
using Heat1D

const EPS = eps(Float64)

@testset "stencil-exact-on-quadratics-with-boundaries" begin
    # N = 15, dx = 1/16: u = 2 - x + 3x^2 has u_xx = 6, boundary values 2
    # and 4. Dyadic grid values: exact.
    N, dx = 15, 1 / 16
    x = grid(N)
    u = 2 .- x .+ 3 .* x .^ 2
    @test isequal(second_difference!(zeros(N), u, 2.0, 4.0, dx), fill(6.0, N))
    # Only the first and the last point see the boundary values.
    d2 = second_difference!(zeros(N), zeros(N), 1.0, 3.0, dx)
    @test isequal(d2[1], 256.0) && isequal(d2[N], 768.0) && all(iszero, d2[2:N-1])
    @test isequal(second_difference!(zeros(2), [1.0, 1.0], 1.0, 1.0, 1 / 3), [0.0, 0.0])
end

@testset "explicit-step-source-and-kappa" begin
    # u = 0, source s = x + t, kappa = 5: one step from t = 1/4 gives
    # dt (x_i + 1/4) (exact: dyadic values).
    N, dx, dt = 3, 1 / 4, 1 / 128
    p = HeatProblem(5.0, x -> 0.0, (x, t) -> x + t, t -> 0.0, t -> 0.0)
    @test isequal(ftcs_step!(zeros(N), zeros(N), p, 0.25, dt, dx, zeros(N)), dt .* (grid(N) .+ 0.25))
    # u = x(1 - x), kappa = 5, no source: u_xx = -2, so unew = u - 10 dt (4 eps).
    q = HeatProblem(5.0, x -> 0.0)
    x = grid(N)
    @test isapprox(ftcs_step!(zeros(N), x .* (1 .- x), q, 0.0, dt, dx, zeros(N)), x .* (1 .- x) .- 10dt; atol = 4EPS)
    # The boundary values are taken at the old time: left(t) = t, u = 0.
    r = HeatProblem(1.0, x -> 0.0, (x, t) -> 0.0, t -> t, t -> 0.0)
    unew = ftcs_step!(zeros(N), zeros(N), r, 0.5, dt, dx, zeros(N))
    @test isapprox(unew[1], dt * 0.5 * 16; rtol = 4EPS) && iszero(unew[2])
end

@testset "tridiagonal-solve-known-solution" begin
    # n = 8, a system that is diagonally dominant but not symmetric, with
    # the right-hand side built from a known solution. Elimination without
    # pivoting is backward stable here (diagonal dominance) and the
    # condition number is below 10: error <= 64 eps relative.
    n = 8
    a = [0.0; [-1.0 - 0.1i for i in 2:n]]
    b = [5.0 + 0.5i for i in 1:n]
    c = [[-2.0 + 0.1i for i in 1:n-1]; 0.0]
    xt = [Float64(i^2 - 3i) for i in 1:n]
    d = [b[i] * xt[i] + (i > 1 ? a[i] * xt[i-1] : 0.0) + (i < n ? c[i] * xt[i+1] : 0.0) for i in 1:n]
    @test isapprox(thomas!(zeros(n), copy(a), copy(b), copy(c), copy(d)), xt; rtol = 64EPS)
    # The right-hand side is eliminated: a lower-bidiagonal system.
    @test isapprox(thomas!(zeros(3), [0.0, 1.0, 1.0], [1.0, 1.0, 1.0], [0.0, 0.0, 0.0], [1.0, 2.0, 3.0]),
                   [1.0, 1.0, 2.0]; rtol = 4EPS)
end

@testset "manufactured-problem-is-consistent" begin
    # The exact solution satisfies the problem's initial and boundary data,
    # and its residual u_t - kappa u_xx - s vanishes, checked by central
    # differences with h = 1e-4 (error ~1e-7 for these smooth functions,
    # see the visible test): tolerance 1e-6, at kappa = 2.5.
    p, ex = mms_problem(2.5)
    @test isapprox(p.kappa, 2.5; rtol = EPS)
    for (x, t) in ((0.1, 0.0), (0.5, 0.7), (0.9, 2.0))
        @test isapprox(p.u0(x), ex(x, 0.0); rtol = 4EPS)
        h = 1e-4
        ut = (ex(x, t + h) - ex(x, t - h)) / 2h
        uxx = (ex(x + h, t) - 2ex(x, t) + ex(x - h, t)) / h^2
        @test isapprox(p.source(x, t), ut - 2.5 * uxx; atol = 1e-6)
    end
    @test isapprox(p.right(1.3), ex(1.0, 1.3); rtol = 4EPS) && isapprox(p.left(1.3), ex(0.0, 1.3); atol = 4EPS)
end
