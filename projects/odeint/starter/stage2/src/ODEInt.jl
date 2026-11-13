"""
    ODEInt

An explicit Runge-Kutta integrator written from scratch: the Dormand-Prince
5(4) pair (Hairer, Norsett and Wanner, *Solving ODEs I*, section II.5, the
DOPRI5 code), fixed-step and adaptive, plus the Stormer-Verlet method and the
Kepler problem, so that the two can be compared on long orbits.

Conventions: a right-hand side is `f!(du, u, t)` and writes du/dt into `du`;
an acceleration is `accel!(a, q)`. States are `Vector{Float64}`. Every
solver counts its right-hand-side (or force) evaluations in `nf`, the cost
measure the case project compares methods by.
"""
module ODEInt

export DP54Cache, dp54_step!, error_norm, propose_step, initial_step,
       solve_fixed, solve_adaptive, verlet_step!, solve_verlet,
       kepler_rhs!, kepler_accel!, kepler_energy, kepler_angmom, kepler_initial, kepler_exact,
       fit_order

# ---- the Dormand-Prince 5(4) tableau ----------------------------------------------------
#
# Hairer, Norsett, Wanner I, Table II.5.2. The 5th-order weights B are the
# last row of A (the "first same as last" property: stage 7 is f at the new
# point, so an accepted step's k7 is the next step's k1). E = B - BHAT, the
# weights of the error estimate y5 - y4.

const C2, C3, C4, C5 = 1 / 5, 3 / 10, 4 / 5, 8 / 9
const A21 = 1 / 5
const A31, A32 = 3 / 40, 9 / 40
const A41, A42, A43 = 44 / 45, -56 / 15, 32 / 9
const A51, A52, A53, A54 = 19372 / 6561, -25360 / 2187, 64448 / 6561, -212 / 729
const A61, A62, A63, A64, A65 = 9017 / 3168, -355 / 33, 46732 / 5247, 49 / 176, -5103 / 18656
const A71, A73, A74, A75, A76 = 35 / 384, 500 / 1113, 125 / 192, -2187 / 6784, 11 / 84
const E1, E3, E4, E5, E6, E7 = 71 / 57600, -71 / 16695, 71 / 1920, -17253 / 339200, 22 / 525, -1 / 40

"""
    DP54Cache(n)

Work arrays for one Dormand-Prince step on a state of length `n`: the seven
stage derivatives `k1` ... `k7`, a stage state `ytmp`, the new solution
`ynew` and the error estimate `err`. Allocated once per solve, so a step
allocates nothing.
"""
struct DP54Cache
    k1::Vector{Float64}
    k2::Vector{Float64}
    k3::Vector{Float64}
    k4::Vector{Float64}
    k5::Vector{Float64}
    k6::Vector{Float64}
    k7::Vector{Float64}
    ytmp::Vector{Float64}
    ynew::Vector{Float64}
    err::Vector{Float64}
end
DP54Cache(n::Integer) = DP54Cache((zeros(n) for _ in 1:10)...)

"""
    dp54_step!(c::DP54Cache, f!, t, y, h) -> nothing

One Dormand-Prince 5(4) step of size `h` from `(t, y)`.

On entry `c.k1` must hold `f(t, y)` (the caller evaluates it once; after an
accepted step it is the previous step's `k7`). The step evaluates stages 2 to
7: stage `i` is `f!(c.ki, ytmp, t + Ci*h)` with
`ytmp = y + h * (Ai1*k1 + ... + Ai(i-1)*k(i-1))`, using the constants
`A21` ... `A76` and `C2` ... `C5` of this module (stages 6 and 7 are at
`t + h`). Stage 7 is evaluated at the new solution itself.

On return:
* `c.ynew` is the 5th-order solution `y + h * (A71*k1 + A73*k3 + ... + A76*k6)`
  at `t + h`;
* `c.k7` is `f(t + h, c.ynew)`;
* `c.err` is the error estimate `y5 - y4 = h * (E1*k1 + E3*k3 + ... + E7*k7)`.

`y` is not modified. Exactly 6 calls to `f!`; allocates nothing (use
in-place broadcasts such as `@. c.ytmp = y + h * (A21 * c.k1)`).
"""
function dp54_step!(c::DP54Cache, f!, t, y, h)
    error("TODO(hole:dp54_step)")
end

"""
    error_norm(err, y, ynew, atol, rtol) -> Float64

The scaled root-mean-square norm an adaptive step is judged by (Hairer I,
eq. II.4.11):

    sqrt( (1/n) * sum_i ( err[i] / sc[i] )^2 ),   sc[i] = atol + rtol * max(|y[i]|, |ynew[i]|)

A value <= 1 means the step meets the tolerance. Scaling each component by
its own size makes the test relative where the solution is large and
absolute where it is near zero. Allocates nothing.
"""
function error_norm(err, y, ynew, atol, rtol)
    error("TODO(hole:error_norm)")
end

"""
    propose_step(h, en; safety = 0.9, facmin = 0.2, facmax = 5.0) -> (accept::Bool, hnew::Float64)

The step-size controller. `en` is the step's `error_norm`. The step is
accepted when `en <= 1`. Whatever the verdict, the next step size is

    hnew = h * clamp(safety * en^(-1/5), facmin, facmax)

(`facmax` when `en == 0`). The exponent is 1/5 because the error estimate
`y5 - y4` is the local error of the 4th-order solution, which is O(h^5): the
step that would have given `en = 1` is `h * en^(-1/5)`, and `safety` aims a
little below it. The clamp stops one odd estimate from changing `h` wildly.
"""
function propose_step(h, en; safety = 0.9, facmin = 0.2, facmax = 5.0)
    error("TODO(hole:propose_step)")
end

"""
    initial_step(f!, t0, y0, f0, atol, rtol) -> Float64

A starting step size from the problem itself (Hairer I, section II.4,
"Starting step size"; the DOPRI5 code's HINIT). With the scaled RMS norm
`nrm(v) = sqrt(mean((v[i] / sc[i])^2))`, `sc[i] = atol + rtol * |y0[i]|`:

1. `d0 = nrm(y0)`, `d1 = nrm(f0)`; `h0 = 0.01 * d0 / d1`, or `1e-6` if
   `d0 < 1e-5` or `d1 < 1e-5`;
2. one explicit Euler step: `y1 = y0 + h0 * f0`, `f1 = f(t0 + h0, y1)`
   (one call to `f!`);
3. `d2 = nrm(f1 - f0) / h0`;
4. `h1 = max(1e-6, h0 * 1e-3)` if `max(d1, d2) <= 1e-15`, else
   `h1 = (0.01 / max(d1, d2))^(1/5)`;
5. return `min(100 * h0, h1)`.

`f0` is `f(t0, y0)`.
"""
function initial_step(f!, t0, y0, f0, atol, rtol)
    error("TODO(hole:initial_step)")
end

# ---- solvers ------------------------------------------------------------------------------

"""
    solve_fixed(f!, y0, (t0, tf), n; embedded = false, observe = nothing) -> (y, nf)

`n` equal Dormand-Prince steps from `t0` to `tf` (no error control). Returns
the final state and the number of right-hand-side evaluations (`1 + 6n`).
With `embedded = true` it propagates the embedded 4th-order solution
`y5 - err` instead, so its convergence order can be measured too.
`observe(t, y)`, if given, is called at `t0` and after every step.
"""
function solve_fixed(f!, y0::AbstractVector, tspan, n::Integer; embedded::Bool = false, observe = nothing)
    t0, tf = float.(tspan)
    h = (tf - t0) / n
    y = Vector{Float64}(y0)
    c = DP54Cache(length(y))
    f!(c.k1, y, t0)
    nf = 1
    observe === nothing || observe(t0, y)
    for k in 1:n
        t = t0 + (k - 1) * h
        dp54_step!(c, f!, t, y, h)
        nf += 6
        if embedded
            @. y = c.ynew - c.err
            f!(c.k1, y, t + h)     # k7 is f at y5, not at y4: one more evaluation
            nf += 1
        else
            copyto!(y, c.ynew)
            copyto!(c.k1, c.k7)    # first same as last
        end
        observe === nothing || observe(k == n ? tf : t0 + k * h, y)
    end
    return y, nf
end

"""
    solve_adaptive(f!, y0, (t0, tf); rtol = 1e-6, atol = 1e-6, h0 = nothing,
                   maxsteps = 1_000_000, observe = nothing) -> NamedTuple

Adaptive Dormand-Prince 5(4) from `t0` to `tf > t0`. Returns
`(y, t, nf, naccept, nreject)`: the state at `tf`, the final time (exactly
`tf`), the number of `f!` calls, and the accepted and rejected step counts.

* Evaluate `f(t0, y0)` into a `DP54Cache`'s `k1`; the first step is `h0`, or
  `initial_step(...)` when `h0 === nothing` (one more `f!` call).
* Repeat until `t == tf`: shorten the step to `tf - t` if it would pass `tf`
  (and then set `t = tf` exactly on acceptance, not `t + h`); take a
  `dp54_step!`; judge it with `error_norm(c.err, y, c.ynew, atol, rtol)` and
  `propose_step`. On acceptance move to `c.ynew`, copy `k7` into `k1`
  (first same as last) and call `observe(t, y)` if given; on rejection keep
  `t`, `y` and `k1`. Either way continue with the proposed step, except that
  the step after a rejection may not grow (`facmax = 1`, as DOPRI5 does).
* Throw an `ErrorException` if more than `maxsteps` steps (accepted plus
  rejected) are attempted.

`observe(t0, y0)` is also called once before the first step.
"""
function solve_adaptive(f!, y0::AbstractVector, tspan; rtol = 1e-6, atol = 1e-6, h0 = nothing,
                        maxsteps::Integer = 1_000_000, observe = nothing)
    error("TODO(hole:solve_adaptive)")
end

# ---- Stormer-Verlet ----------------------------------------------------------------------

"""
    verlet_step!(q, p, a, h, accel!) -> nothing

One Stormer-Verlet (velocity Verlet, "kick-drift-kick") step of size `h` for
`q'' = accel(q)`, in place:

    p_half = p + (h/2) * a
    q_new  = q + h * p_half
    a_new  = accel(q_new)          # accel!(a, q): the one force evaluation
    p_new  = p_half + (h/2) * a_new

On entry `a` must hold `accel(q)`; on return it holds `accel(q_new)`, ready
for the next step. The method is second order, symmetric (time-reversible)
and symplectic. Allocates nothing.
"""
function verlet_step!(q, p, a, h, accel!)
    error("TODO(hole:verlet_step)")
end

"""
    solve_verlet(accel!, q0, p0, (t0, tf), n; observe = nothing) -> (q, p, nf)

`n` equal Stormer-Verlet steps. `nf` counts force evaluations (`1 + n`).
`observe(t, q, p)`, if given, is called at `t0` and after every step.
"""
function solve_verlet(accel!, q0::AbstractVector, p0::AbstractVector, tspan, n::Integer; observe = nothing)
    t0, tf = float.(tspan)
    h = (tf - t0) / n
    q, p = Vector{Float64}(q0), Vector{Float64}(p0)
    a = similar(q)
    accel!(a, q)
    observe === nothing || observe(t0, q, p)
    for k in 1:n
        verlet_step!(q, p, a, h, accel!)
        observe === nothing || observe(k == n ? tf : t0 + k * h, q, p)
    end
    return q, p, 1 + n
end

# ---- the Kepler problem ---------------------------------------------------------------------
#
# Units: gravitational parameter GM = 1 and semi-major axis a = 1, so the
# period is 2*pi and the energy of every orbit is -1/2 (E = -GM / 2a).
# State u = [q1, q2, p1, p2] (position, velocity).

"""`a = -q / |q|^3`: the acceleration of the Kepler problem (GM = 1)."""
function kepler_accel!(a, q)
    r2 = q[1]^2 + q[2]^2
    s = -1 / (r2 * sqrt(r2))
    a[1] = s * q[1]
    a[2] = s * q[2]
    return nothing
end

"""`f!` for the Kepler problem as a first-order system in `u = [q1, q2, p1, p2]`."""
function kepler_rhs!(du, u, t)
    du[1] = u[3]
    du[2] = u[4]
    r2 = u[1]^2 + u[2]^2
    s = -1 / (r2 * sqrt(r2))
    du[3] = s * u[1]
    du[4] = s * u[2]
    return nothing
end

"""Energy `|p|^2/2 - 1/|q|`; `-1/2` on every orbit of semi-major axis 1."""
kepler_energy(q, p) = (p[1]^2 + p[2]^2) / 2 - 1 / sqrt(q[1]^2 + q[2]^2)
kepler_energy(u) = kepler_energy(view(u, 1:2), view(u, 3:4))

"""Angular momentum `q1*p2 - q2*p1`; `sqrt(1 - e^2)` for eccentricity `e`."""
kepler_angmom(q, p) = q[1] * p[2] - q[2] * p[1]
kepler_angmom(u) = kepler_angmom(view(u, 1:2), view(u, 3:4))

"""
    kepler_initial(e) -> Vector{Float64}

`[q1, q2, p1, p2]` at perihelion of the orbit with eccentricity `0 <= e < 1`
and semi-major axis 1: `q = (1 - e, 0)`, `p = (0, sqrt((1 + e) / (1 - e)))`.
"""
function kepler_initial(e)
    0 <= e < 1 || throw(DomainError(e, "eccentricity must be in [0, 1)"))
    return [1 - e, 0.0, 0.0, sqrt((1 + e) / (1 - e))]
end

"""
    kepler_exact(e, t) -> Vector{Float64}

The exact state `[q1, q2, p1, p2]` at time `t` of the orbit that starts at
`kepler_initial(e)` at `t = 0` (GM = 1, semi-major axis 1, period 2*pi).

Solve Kepler's equation `E - e*sin(E) = M` for the eccentric anomaly `E`,
where the mean anomaly is `M = t` reduced to [-pi, pi] (use
`rem2pi(t, RoundNearest)`), by Newton's method from `E = M + 0.85*e*sign(sin(M))`
until the update is below `4*eps()` (at most 50 iterations). Then

    q = (cos(E) - e,  sqrt(1 - e^2) * sin(E))
    p = (-sin(E),     sqrt(1 - e^2) * cos(E)) / (1 - e*cos(E))
"""
function kepler_exact(e, t)
    error("TODO(hole:kepler_exact)")
end

# ---- measuring a convergence order ----------------------------------------------------------

"""
    fit_order(hs, errs) -> Float64

The observed order of convergence: the least-squares slope of `log(errs)`
against `log(hs)` over all the points given (at least two, all positive).
For errors that behave like `C * h^p` the slope is `p`. Which points to pass
(the fit range) is the caller's decision: points where rounding dominates,
or where `h` is too large for the asymptotic regime, bend the line.
"""
function fit_order(hs, errs)
    error("TODO(hole:fit_order)")
end

end # module ODEInt
