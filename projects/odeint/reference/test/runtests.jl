# Behavioural specification of ODEInt.
#
# Verification by four kinds of evidence, each with its tolerance derived in
# a comment (invariant 9):
# * exact solutions: problems the method solves without truncation error
#   (polynomial integrands, nilpotent linear systems, the stability
#   polynomial), so only rounding is left;
# * measured convergence orders (least-squares fits of log error on log h)
#   against the theoretical order;
# * tolerance proportionality of the adaptive solver;
# * conservation: energy drift on the Kepler problem, linear for DP5(4),
#   bounded for Stormer-Verlet.
# Nothing is random. Exact identities that hold by construction (an integer
# count, landing on tf) are compared exactly and say why.

using Test
using ODEInt
using ODEInt: A21, C2, C3, C4, C5, E1, E3, E4, E5, E6, E7

const EPS = eps(Float64)
const TWO_PI = 2 * pi

"""f! that counts its calls, for checking evaluation counts."""
mutable struct Counted{F}
    f!::F
    n::Int
end
(c::Counted)(du, u, t) = (c.n += 1; c.f!(du, u, t))

lin!(lam) = (du, u, t) -> (du[1] = lam * u[1]; nothing)

# The 7 stages as one step from y with FSAL k1 set; returns the cache.
function one_step(f!, t, y, h)
    c = DP54Cache(length(y))
    f!(c.k1, y, t)
    dp54_step!(c, f!, t, y, h)
    return c
end

@testset "tableau: consistency and quadrature order" begin
    # Row sums of A equal the nodes c (the method sees time correctly), and
    # the error weights sum to zero (the error estimate of y' = const is 0).
    # These are sums of <= 6 doubles of size <= 12: rounding <= 6 * 12 * eps.
    @test isapprox(A21, C2; atol = 100EPS)
    @test isapprox(3 / 40 + 9 / 40, C3; atol = 100EPS)
    @test isapprox(44 / 45 - 56 / 15 + 32 / 9, C4; atol = 100EPS)
    @test isapprox(19372 / 6561 - 25360 / 2187 + 64448 / 6561 - 212 / 729, C5; atol = 100EPS)
    @test isapprox(E1 + E3 + E4 + E5 + E6 + E7, 0.0; atol = 100EPS)
end

@testset "dp54_step: stability polynomial on y' = lambda*y" begin
    # For y' = lambda*y one DP5 step is y -> R(z) y with z = h*lambda and
    # R(z) = 1 + z + z^2/2 + z^3/6 + z^4/24 + z^5/120 + z^6/600 (b'A^k 1 for
    # the DOPRI5 tableau, computed in exact rational arithmetic), and the
    # embedded solution has error estimate
    #   y5 - y4 = -97/120000 z^5 + 39/120000 z^6 - 1/24000 z^7.
    # Both are exact identities, so only rounding is left. y5 is a sum of 7
    # terms of size <= 2 built by <= 30 flops each: |rounding| <= 30 * eps
    # relative (bound 64 eps). err is h * sum(E_i k_i) with |k_i| <= 2 and
    # |E_i| <= 0.06: rounding <= 7 * 2 * 0.06 * h * 4 eps < 4 h eps (bound 16 h eps).
    R(z) = evalpoly(z, (1, 1, 1 / 2, 1 / 6, 1 / 24, 1 / 120, 1 / 600))
    Rerr(z) = evalpoly(z, (0, 0, 0, 0, 0, -97 / 120000, 39 / 120000, -1 / 24000))
    for lam in (-1.0, 1.0, -3.0), h in (0.1, 0.25)
        f! = Counted(lin!(lam), 0)
        y = [1.0]
        c = one_step(f!, 0.0, y, h)
        @test f!.n == 7                         # 1 for k1 (the caller) + 6 in the step
        @test isapprox(c.ynew[1], R(h * lam); rtol = 64EPS)
        @test isapprox(c.err[1], Rerr(h * lam); atol = 16 * h * EPS)
        @test isapprox(c.k7[1], lam * c.ynew[1]; rtol = 4EPS)   # k7 = f(t+h, ynew): one product
        @test y == [1.0]                        # y is not modified (exact: never written)
    end
end

@testset "dp54_step: stage times on a polynomial integrand" begin
    # y' = 5 t^4 has y = t^5. DP5's weights integrate polynomials of degree
    # <= 4 exactly (b'c^k = 1/(k+1) for k <= 4), so one step is exact up to
    # rounding; this needs every stage evaluated at its own time t + c_i h.
    # The embedded weights are exact for degree <= 3 only: for 5 t^4 the
    # estimate is exactly 5 h^5 (1/5 - bhat'c^4) = (71/54000) h^5, and for
    # 4 t^3 it is 0. Values are O(1) after <= 40 flops: bound 64 eps.
    for (t0, h) in ((0.0, 1.0), (0.3, 0.7), (-1.2, 0.5))
        c = one_step((du, u, t) -> (du[1] = 5t^4; nothing), t0, [t0^5], h)
        @test isapprox(c.ynew[1], (t0 + h)^5; atol = 64EPS * (1 + abs(t0) + h)^5)
        @test isapprox(c.err[1], 71 / 54000 * h^5; atol = 64EPS * (1 + abs(t0) + h)^5)
        c3 = one_step((du, u, t) -> (du[1] = 4t^3; nothing), t0, [t0^4], h)
        @test isapprox(c3.err[1], 0.0; atol = 64EPS * (1 + abs(t0) + h)^4)
    end
end

@testset "exact solutions: nilpotent linear system" begin
    # y' = J y with J the 6x6 shift (y_i' = y_{i+1}, y_6' = 0) has the
    # polynomial solution y_i(t) = sum_{k=0}^{6-i} t^k/k! (from y0 = ones).
    # One DP5 step maps y -> R(hJ) y, and R agrees with exp up to z^5 while
    # J^6 = 0, so R(hJ) = exp(hJ): the method is exact for any step count.
    # Rounding: each step does ~7 stages x 7 terms on values <= max|y|,
    # <= 50 eps relative per step, accumulating at most linearly over n
    # steps, so the bound is 50 * n * eps * max|y|.
    shift!(du, u, t) = (for i in 1:5; du[i] = u[i+1]; end; du[6] = 0.0; nothing)
    tf = 2.0
    exact = [sum(tf^k / factorial(k) for k in 0:(6-i)) for i in 1:6]
    for n in (1, 3, 7)
        y, nf = solve_fixed(shift!, ones(6), (0.0, tf), n)
        @test nf == 1 + 6n                      # integer count: FSAL saves one per step
        @test isapprox(y, exact; atol = 50 * n * EPS * maximum(exact), norm = v -> maximum(abs, v))
    end
end

@testset "convergence: DP5 is order 5 on the Kepler problem" begin
    # One period of the e = 0.5 orbit against kepler_exact. Fit range:
    # 200 to 1600 steps (h = 3.1e-2 to 3.9e-3): above it the error is
    # pre-asymptotic (local slopes 8.2, 4.9 at n = 50, 100); below it the
    # error approaches rounding (~1e-13). Measured fit: 5.15. The window
    # [4.7, 5.4] is set by the measured local slopes in the range (4.81 to
    # 5.21) plus a margin for rounding differences between correct
    # implementations; order 4 (one wrong 5th-order weight) falls outside.
    e = 0.5
    u0, uT = kepler_initial(e), kepler_exact(e, TWO_PI)
    ns = (200, 400, 800, 1600)
    hs = [TWO_PI / n for n in ns]
    errs = [maximum(abs, solve_fixed(kepler_rhs!, u0, (0.0, TWO_PI), n)[1] .- uT) for n in ns]
    p = fit_order(hs, errs)
    @test 4.7 <= p <= 5.4
end

@testset "convergence: the error estimate is O(h^5)" begin
    # On y' = -y the estimate is -97/120000 z^5 + O(z^6) (see the stability
    # test), so log|err| against log h has slope 5 + O(h): for h in
    # [0.0125, 0.1] the z^6 term changes the local slope by at most
    # log2(1 + 0.4 * 0.1) < 0.06. Window 5 +- 0.15.
    hs = [0.1, 0.05, 0.025, 0.0125]
    errs = [abs(one_step(lin!(-1.0), 0.0, [1.0], h).err[1]) for h in hs]
    @test 4.85 <= fit_order(hs, errs) <= 5.15
end

@testset "error_norm: scaled RMS" begin
    # Exact cases: sc = atol + rtol*max(|y|, |ynew|) computed with 2 flops,
    # each ratio and the mean with a few more: <= 8 eps relative.
    atol, rtol = 1e-6, 1e-3
    y, ynew = [1.0, -2.0, 0.0, 4.0], [1.5, -1.0, -3.0, 4.0]
    sc = [atol + rtol * max(abs(a), abs(b)) for (a, b) in zip(y, ynew)]
    @test error_norm(zeros(4), y, ynew, atol, rtol) == 0           # exact: a sum of zeros
    @test isapprox(error_norm(sc, y, ynew, atol, rtol), 1.0; rtol = 8EPS)
    @test isapprox(error_norm(-3 .* sc, y, ynew, atol, rtol), 3.0; rtol = 8EPS)
    # one component at twice its scale, the others zero: sqrt(4/4) = 1
    @test isapprox(error_norm([2sc[1], 0, 0, 0], y, ynew, atol, rtol), 1.0; rtol = 8EPS)
    # the scale uses the larger of |y| and |ynew| (component 3: y = 0, ynew = -3)
    @test isapprox(error_norm([0, 0, sc[3], 0], y, ynew, atol, rtol), 0.5; rtol = 8EPS)
    @test error_norm(zeros(4), y, ynew, atol, rtol) isa Float64
end

@testset "propose_step: accept, reject, clamp" begin
    # hnew = h * clamp(0.9 * en^(-1/5), 0.2, 5): a power and two products,
    # <= 4 eps relative.
    h = 0.1
    acc, hn = propose_step(h, 1.0)
    @test acc
    @test isapprox(hn, 0.09; rtol = 4EPS)
    @test !propose_step(h, nextfloat(1.0))[1]          # en just above 1: rejected
    @test isapprox(propose_step(h, 0.45^5)[2], 0.2; rtol = 4EPS)    # 0.9 / 0.45 = 2
    @test isapprox(propose_step(h, 32.0)[2], 0.045; rtol = 4EPS)    # 0.9 / 2 = 0.45, rejected
    @test !propose_step(h, 32.0)[1]
    @test isapprox(propose_step(h, 0.0)[2], 0.5; rtol = 4EPS)       # en = 0: facmax
    @test isapprox(propose_step(h, 1e-12)[2], 0.5; rtol = 4EPS)     # clamped at facmax
    @test isapprox(propose_step(h, 1e12)[2], 0.02; rtol = 4EPS)     # clamped at facmin
    @test isapprox(propose_step(h, 1e-12; facmax = 1.0)[2], 0.1; rtol = 4EPS)
end

@testset "initial_step: Hairer's starting step" begin
    # y' = -y, y0 = 1, atol = rtol = 1e-6: sc = 2e-6, d0 = d1 = 5e5,
    # h0 = 0.01, y1 = 0.99, d2 = |-0.99 + 1| / 2e-6 / 0.01 = 5e5,
    # h1 = (0.01 / 5e5)^(1/5) = (2e-8)^(1/5) = 0.0288539..., min(100 h0, h1) = h1.
    # ~20 flops on O(1) ratios: bound 64 eps relative.
    f! = Counted(lin!(-1.0), 0)
    h = initial_step(f!, 0.0, [1.0], [-1.0], 1e-6, 1e-6)
    @test f!.n == 1
    @test isapprox(h, (2e-8)^(1 / 5); rtol = 64EPS)
    # y' = 0 from y0 = 0: d0 = d1 = 0 < 1e-5, so h0 = 1e-6; d2 = 0, so
    # h1 = max(1e-6, 1e-9) = 1e-6 and the result is min(1e-4, 1e-6) = 1e-6.
    z! = (du, u, t) -> (du .= 0; nothing)
    @test isapprox(initial_step(z!, 0.0, [0.0, 0.0], [0.0, 0.0], 1e-6, 1e-6), 1e-6; rtol = 4EPS)
    # A large state with a slow, constant rate (y' = 1, y0 = 1e6, atol =
    # rtol = 1e-6): sc = 1e-6 + 1e-6 * 1e6, d0 = 1e6 / sc, d1 = 1 / sc,
    # h0 = 0.01 * d0 / d1 = 1e4; f1 = f0, so d2 = 0 and
    # h1 = (0.01 / d1)^(1/5) = (0.01 * sc)^(1/5) ~ 0.398 < 100 * h0.
    one! = (du, u, t) -> (du .= 1; nothing)
    sc = 1e-6 + 1e-6 * 1e6
    @test isapprox(initial_step(one!, 0.0, [1e6], [1.0], 1e-6, 1e-6), (0.01 / (1 / sc))^(1 / 5); rtol = 64EPS)
end

@testset "solve_adaptive: lands on tf and counts its work" begin
    f! = Counted(lin!(-1.0), 0)
    tf = 3.0
    r = solve_adaptive(f!, [1.0], (0.0, tf); rtol = 1e-8, atol = 1e-8)
    @test r.t === tf                     # exact by specification: the last step sets t = tf
    @test r.naccept > 0
    @test r.nf == f!.n                   # integer counts
    @test r.nf == 2 + 6 * (r.naccept + r.nreject)   # k1, the starting-step trial, 6 per attempt
    # tolerance-proportional global error (~400 tol on Kepler, below): 1e3 tol
    @test isapprox(r.y[1], exp(-tf); atol = 1e3 * 1e-8)
    g! = Counted(lin!(-1.0), 0)
    r2 = solve_adaptive(g!, [1.0], (0.0, tf); rtol = 1e-8, atol = 1e-8, h0 = 1.0)
    @test r2.nreject > 0                 # h0 = 1 is far too large at 1e-8: rejected first
    @test r2.nf == 1 + 6 * (r2.naccept + r2.nreject)
    @test isapprox(r2.y[1], exp(-tf); atol = 1e3 * 1e-8)
    @test_throws ErrorException solve_adaptive(lin!(-1.0), [1.0], (0.0, tf); rtol = 1e-12, atol = 1e-12, maxsteps = 5)
    # observe sees t0 and every accepted step, ending at tf
    ts = Float64[]
    r3 = solve_adaptive(lin!(-1.0), [1.0], (0.0, tf); observe = (t, y) -> push!(ts, t))
    @test length(ts) == r3.naccept + 1
    @test issorted(ts) && ts[end] === tf
end

@testset "solve_adaptive: error is proportional to the tolerance" begin
    # DOPRI5 controls the local error of the 4th-order estimate (O(h^5)),
    # so h ~ tol^(1/5) and the 5th-order global error ~ h^5 ~ tol: the slope
    # of log(global error) on log(tol) is 1 in the asymptotic range.
    # Measured on one period of the e = 0.5 orbit, tol = 1e-5 ... 1e-10:
    # slope 1.03, error/tol between 228 and 443. Window [0.85, 1.2] for the
    # slope; 1e3 * tol for the size (calibrated on this deterministic
    # problem: the largest observed ratio is 443).
    e = 0.5
    u0, uT = kepler_initial(e), kepler_exact(e, TWO_PI)
    tols = [10.0^-k for k in 5:10]
    errs = [maximum(abs, solve_adaptive(kepler_rhs!, u0, (0.0, TWO_PI); rtol = tol, atol = tol).y .- uT) for tol in tols]
    @test 0.85 <= fit_order(tols, errs) <= 1.2
    @test all(errs .<= 1e3 .* tols)
end

@testset "kepler_exact: Kepler's equation and the conserved quantities" begin
    # Newton converges to |dE| <= 4 eps; each component is then a few flops
    # on O(1) values (for e <= 0.7, 1/(1 - e cos E) <= 1/0.3): bound 64 eps.
    for e in (0.0, 0.3, 0.7)
        @test isapprox(kepler_exact(e, 0.0), kepler_initial(e); atol = 64EPS)
        @test isapprox(kepler_exact(e, TWO_PI), kepler_initial(e); atol = 64EPS)
        # aphelion at half a period: q = (-(1 + e), 0)
        @test isapprox(kepler_exact(e, pi)[1:2], [-(1 + e), 0.0]; atol = 64EPS)
        for t in (0.4, 1.7, 3.9, 25.0)
            u = kepler_exact(e, t)
            @test isapprox(kepler_energy(u), -0.5; atol = 64EPS)
            @test isapprox(kepler_angmom(u), sqrt(1 - e^2); atol = 64EPS)
            # Every point of the ellipse has the right energy, so check the
            # timing too: recover E from the position (cos E = q1 + e,
            # sin E = q2 / sqrt(1 - e^2)) and test Kepler's equation
            # E - e sin E = M. atan of O(1) values plus 3 flops: 64 eps
            # (for e = 0.7 the 1/sqrt(1 - e^2) = 1.4 amplification included).
            E = atan(u[2] / sqrt(1 - e^2), u[1] + e)
            @test isapprox(E - e * sin(E), rem2pi(t, RoundNearest); atol = 64EPS)
        end
    end
end

@testset "kepler_exact: agrees with an accurate numerical solution" begin
    # It solves the ODE: against the adaptive solver at tol 1e-12 over
    # 1.3 time units (error ~ 443 * tol per period, measured): 1e-9.
    for e in (0.2, 0.7)
        r = solve_adaptive(kepler_rhs!, kepler_initial(e), (0.0, 1.3); rtol = 1e-12, atol = 1e-12)
        @test isapprox(r.y, kepler_exact(e, 1.3); atol = 1e-9, norm = v -> maximum(abs, v))
    end
end

@testset "verlet_step: the exact map on the harmonic oscillator" begin
    # For q'' = -q one kick-drift-kick step is the linear map
    #   [q; p] -> [1 - h^2/2, h; -h(1 - h^2/4), 1 - h^2/2] [q; p],
    # with determinant 1 (area preserving). A few flops: bound 8 eps.
    ho!(a, q) = (a .= -q; nothing)
    h = 0.3
    M = [1-h^2/2 h; -h*(1 - h^2 / 4) 1-h^2/2]
    for (q0, p0) in ((1.0, 0.0), (0.0, 1.0), (0.6, -0.8))
        q, p, a = [q0], [p0], [-q0]
        verlet_step!(q, p, a, h, ho!)
        @test isapprox([q[1], p[1]], M * [q0, p0]; atol = 8EPS)
        @test isapprox(a[1], -q[1]; atol = 8EPS)    # a = accel(q_new) on return
    end
    # Time-reversible: a step of h then one of -h returns to the start
    # (rounding of ~10 flops per step on O(1) values: 16 eps).
    q, p = [1.0 - 0.5, 0.0], [0.0, sqrt(1.5 / 0.5)]
    q0, p0 = copy(q), copy(p)
    a = similar(q); kepler_accel!(a, q)
    verlet_step!(q, p, a, 0.05, kepler_accel!)
    verlet_step!(q, p, a, -0.05, kepler_accel!)
    @test isapprox([q; p], [q0; p0]; atol = 16EPS * 8)   # |p| ~ 1.7, 1/r^2 ~ 4 near perihelion
end

@testset "convergence: Stormer-Verlet is order 2" begin
    # Circular orbit (e = 0), one period, n = 100 ... 800 steps: the error
    # is C h^2 (1 + O(h^2)); with h <= 0.063 the h^2 correction moves the
    # slope by < 0.01. Window 2 +- 0.1.
    u0, uT = kepler_initial(0.0), kepler_exact(0.0, TWO_PI)
    ns = (100, 200, 400, 800)
    errs = map(ns) do n
        q, p, nf = solve_verlet(kepler_accel!, u0[1:2], u0[3:4], (0.0, TWO_PI), n)
        @test nf == 1 + n
        maximum(abs, [q; p] .- uT)
    end
    @test 1.9 <= fit_order([TWO_PI / n for n in ns], errs) <= 2.1
end

@testset "energy: DP5 drifts linearly, Stormer-Verlet stays bounded" begin
    # Running maximum of |E(t) - E0| / |E0| at the end of orbit k, e = 0.5.
    # Theory: a non-symplectic method's energy error accumulates at the same
    # rate every orbit, so it grows like t (exponent 1); Stormer-Verlet
    # conserves a modified energy H + O(h^2) exactly (backward error
    # analysis), so its energy error stays O(h^2) for all time (exponent 0).
    # Measured exponents (k = 10 ... 160): 1.000 and 0.000. Windows: 1 +- 0.1,
    # and a Verlet ratio max(k=160) / max(k=10) in [0.99, 1.01] (rounding
    # adds a random walk of ~ eps * sqrt(steps) ~ 1e-13, far below 1e-3).
    e = 0.5
    u0 = kepler_initial(e)
    E0 = kepler_energy(u0)
    orbits = (10, 20, 40, 80, 160)
    function dp_maxes(nper)
        m = 0.0
        y = copy(u0)
        out = Float64[]
        for k in 1:last(orbits)
            y, _ = solve_fixed(kepler_rhs!, y, ((k - 1) * TWO_PI, k * TWO_PI), nper;
                               observe = (t, u) -> (m = max(m, abs(kepler_energy(u) - E0) / abs(E0))))
            k in orbits && push!(out, m)
        end
        return out
    end
    function verlet_maxes(nper)
        m = 0.0
        q, p = u0[1:2], u0[3:4]
        out = Float64[]
        for k in 1:last(orbits)
            q, p, _ = solve_verlet(kepler_accel!, q, p, ((k - 1) * TWO_PI, k * TWO_PI), nper;
                                   observe = (t, qq, pp) -> (m = max(m, abs(kepler_energy(qq, pp) - E0) / abs(E0))))
            k in orbits && push!(out, m)
        end
        return out
    end
    ts = [k * TWO_PI for k in orbits]
    dp = dp_maxes(100)
    @test 0.9 <= fit_order(ts, dp) <= 1.1
    v = verlet_maxes(200)
    @test 0.99 <= v[end] / v[1] <= 1.01
    # Verlet's bound is O(h^2): halving h divides it by 4 (+ O(h^2) relative:
    # h = 2pi/200 gives < 0.1%; window 4 +- 0.2).
    v2 = verlet_maxes(400)
    @test 3.8 <= v[1] / v2[1] <= 4.2
end

@testset "fit_order: least squares on log-log" begin
    # Exact power laws: the slope is the exponent; ~10 logs and flops on
    # O(1) values: 64 eps relative.
    hs = [0.1, 0.05, 0.025, 0.0125]
    @test isapprox(fit_order(hs, 3 .* hs .^ 4), 4.0; rtol = 64EPS)
    @test isapprox(fit_order(hs, 0.5 .* hs .^ 2), 2.0; rtol = 64EPS)
    # A bent line: x = 0:3, y = [0, 3, 3, 3] (in units of log 2) has the
    # least-squares slope 4.5 / 5 = 0.9, while its endpoints give 1.
    @test isapprox(fit_order(2.0 .^ (0:3), 2.0 .^ [0, 3, 3, 3]), 0.9; rtol = 64EPS)
    @test_throws ArgumentError fit_order([0.1], [0.2])
    @test_throws ArgumentError fit_order([0.1, 0.2], [0.0, 0.1])
end
