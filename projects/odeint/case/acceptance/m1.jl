# Hidden acceptance tests, milestone 1 (stage-1 holes: dp54_step, error_norm,
# kepler_exact, verlet_step). Different problems from the visible tests in
# the starter, so code fitted to those does not pass by accident. Every
# tolerance is derived in a comment; nothing is random.

using Test
using ODEInt

const EPS = eps(Float64)
const TWO_PI = 2 * pi

function one_step(f!, t, y, h)
    c = DP54Cache(length(y))
    f!(c.k1, y, t)
    dp54_step!(c, f!, t, y, h)
    return c
end

@testset "step-exact-cubic-system" begin
    # y1' = y2, y2' = 6t: y2 = 3t^2 + c2 and y1 = t^3 + c2 t + c1. The
    # integrands are polynomials of degree <= 2 in t (through y2), so both
    # the 5th- and 4th-order formulas are exact: ynew is exact and the
    # error estimate vanishes. ~40 flops on values <= 30: bound 64 eps * 30.
    f!(du, u, t) = (du[1] = u[2]; du[2] = 6t; nothing)
    for (t0, h) in ((0.5, 0.8), (-1.0, 2.0))
        y0 = [t0^3 + t0 + 1, 3t0^2 + 1]
        c = one_step(f!, t0, y0, h)
        t1 = t0 + h
        @test isapprox(c.ynew, [t1^3 + t1 + 1, 3t1^2 + 1]; atol = 64EPS * 30)
        @test isapprox(c.err, [0.0, 0.0]; atol = 64EPS * 30)
    end
end

@testset "step-error-estimate-scale" begin
    # y' = 5t^4 from (0, 0): the 5th-order weights integrate t^4 exactly
    # (ynew = h^5) and the 4th-order ones do not. The estimate is
    # err = h * sum_i (b_i - bhat_i) * 5 (c_i h)^4 = (71/54000) h^5, worked
    # out by hand from the tableau. Measured ratio 1 + 7e-15 at both h; seven
    # terms of O(1): 1e-12 relative. An estimate without its factor h is off
    # by 1/h (2x and 4x here).
    f!(du, u, t) = (du[1] = 5t^4; nothing)
    for h in (0.5, 0.25)
        c = one_step(f!, 0.0, [0.0], h)
        @test isapprox(c.ynew[1], h^5; rtol = 64EPS)
        @test isapprox(c.err[1], 71 / 54000 * h^5; rtol = 1e-12)
    end
end

@testset "step-order-nonautonomous" begin
    # y' = cos(t) y, y = exp(sin t), on [0, 10], n = 80 ... 640 fixed steps:
    # measured local slopes 4.92, 4.97, 4.98 (the range is asymptotic and
    # far above rounding, 1e-13). Window 5 +- 0.2: excludes order 4.
    g!(du, u, t) = (du[1] = cos(t) * u[1]; nothing)
    ns = (80, 160, 320, 640)
    errs = [abs(solve_fixed(g!, [1.0], (0.0, 10.0), n)[1][1] - exp(sin(10.0))) for n in ns]
    @test 4.8 <= fit_order([10.0 / n for n in ns], errs) <= 5.2
end

@testset "step-evaluation-count" begin
    # Exactly 6 calls per step (k1 is the caller's): an integer.
    n = Ref(0)
    f!(du, u, t) = (n[] += 1; du .= -u; nothing)
    c = DP54Cache(3)
    y = [1.0, 2.0, 3.0]
    f!(c.k1, y, 0.0)
    n[] = 0
    dp54_step!(c, f!, 0.0, y, 0.1)
    @test n[] == 6
    @test y == [1.0, 2.0, 3.0]          # input untouched (never written: exact)
end

@testset "norm-homogeneous-and-scaled" begin
    # error_norm is positively homogeneous in err and uses
    # sc = atol + rtol * max(|y|, |ynew|). A few flops per component: 8 eps.
    y, ynew = [0.0, 10.0, -1.0], [2.0, -20.0, -1.0]
    atol, rtol = 1e-8, 1e-4
    sc = atol .+ rtol .* max.(abs.(y), abs.(ynew))
    err = [3e-5, -1e-4, 2e-6]
    want = sqrt(sum((err ./ sc) .^ 2) / 3)
    @test isapprox(error_norm(err, y, ynew, atol, rtol), want; rtol = 8EPS)
    @test isapprox(error_norm(7 .* err, y, ynew, atol, rtol), 7want; rtol = 8EPS)
    # pure absolute control when rtol = 0
    @test isapprox(error_norm(err, y, ynew, 1e-6, 0.0), sqrt(sum((err ./ 1e-6) .^ 2) / 3); rtol = 8EPS)
end

@testset "kepler-high-eccentricity" begin
    # e = 0.9: Newton from E = M + 0.85 e sign(sin M) still converges.
    # Kepler's equation, energy and angular momentum to 64 eps / (1 - e)
    # (the velocity has a 1/(1 - e cos E) <= 10 factor).
    e = 0.9
    for t in (0.05, 1.0, 3.0, 3.1, 6.2, 100.0)
        u = kepler_exact(e, t)
        E = atan(u[2] / sqrt(1 - e^2), u[1] + e)
        @test isapprox(E - e * sin(E), rem2pi(t, RoundNearest); atol = 64EPS / (1 - e))
        @test isapprox(kepler_energy(u), -0.5; atol = 64EPS / (1 - e)^2)
        @test isapprox(kepler_angmom(u), sqrt(1 - e^2); atol = 64EPS / (1 - e))
    end
end

@testset "kepler-solves-the-ode" begin
    # Against fixed-step DP5 with 4000 steps over 4 time units at e = 0.6:
    # h = 1e-3, measured 4.7e-15 on the reference (DP5 is at rounding here,
    # so this tests kepler_exact). Bound 1e-9: a wrong Kepler solve (wrong
    # anomaly, too few Newton iterations) is off by 1e-3 or more, and a
    # correct one with a looser Newton stop (1e-12) still passes.
    e, tf = 0.6, 4.0
    y, _ = solve_fixed(kepler_rhs!, kepler_initial(e), (0.0, tf), 4000)
    @test isapprox(y, kepler_exact(e, tf); atol = 1e-9, norm = v -> maximum(abs, v))
end

@testset "verlet-order-and-bounded-energy" begin
    # e = 0.3: global error after one period at n = 200 ... 1600 steps,
    # order 2 (the h^2 correction moves the slope by < 0.02 here):
    # window 2 +- 0.1. Energy over 50 orbits at n = 300 per orbit: the
    # running maximum is set in the first orbit and does not grow
    # (bounded modified energy; rounding ~1e-13 against ~1e-4): ratio of
    # the maxima over orbits 1-50 and orbit 1 within 1 +- 0.01.
    e = 0.3
    u0, uT = kepler_initial(e), kepler_exact(e, TWO_PI)
    ns = (200, 400, 800, 1600)
    errs = map(ns) do n
        q, p, _ = solve_verlet(kepler_accel!, u0[1:2], u0[3:4], (0.0, TWO_PI), n)
        maximum(abs, [q; p] .- uT)
    end
    @test 1.9 <= fit_order([TWO_PI / n for n in ns], errs) <= 2.1
    E0 = kepler_energy(u0)
    maxerr(norbits) = (m = 0.0;
                       solve_verlet(kepler_accel!, u0[1:2], u0[3:4], (0.0, norbits * TWO_PI), 300norbits;
                                    observe = (t, q, p) -> (m = max(m, abs(kepler_energy(q, p) - E0))));
                       m)
    @test 0.99 <= maxerr(50) / maxerr(1) <= 1.01
end

@testset "verlet-one-force-evaluation" begin
    # One call to accel! per step, and `a` holds the new acceleration.
    n = Ref(0)
    acc!(a, q) = (n[] += 1; a .= -4 .* q; nothing)
    q, p, a = [1.0], [0.5], [-4.0]
    verlet_step!(q, p, a, 0.1, acc!)
    @test n[] == 1
    @test isapprox(a[1], -4 * q[1]; atol = 4EPS)
    # The exact map for q'' = -w^2 q with w = 2 (h = 0.1): kick-drift-kick
    # gives q1 = (1 - (wh)^2/2) q0 + h p0. Two flops: 4 eps.
    @test isapprox(q[1], (1 - (0.2)^2 / 2) * 1.0 + 0.1 * 0.5; atol = 4EPS)
end
