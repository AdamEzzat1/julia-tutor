"""
    Heat1D

The heat equation in a rod, written from scratch and verified by the method
of manufactured solutions:

    u_t = kappa u_xx + s(x, t),   0 < x < 1,
    u(0, t) = left(t),  u(1, t) = right(t),  u(x, 0) = u0(x).

Space: N interior points x_i = i dx, dx = 1 / (N + 1), and the second
difference (u[i-1] - 2u[i] + u[i+1]) / dx^2, which is exact on quadratics.
Time: the theta method. theta = 0 is forward Euler (FTCS, explicit, stable
only for r = kappa dt / dx^2 <= 1/2), theta = 1 backward Euler, theta = 1/2
Crank-Nicolson. The implicit steps solve one tridiagonal system per step
with the Thomas algorithm.

Every solver counts its cost in grid-point updates (N per step), the
measure the case project compares methods by.
"""
module Heat1D

export HeatProblem, grid, second_difference!, ftcs_step!, thomas!, ThetaWork, theta_step!,
       solve_heat, mms_problem, fit_order

"""
    HeatProblem(kappa, u0, source, left, right)
    HeatProblem(kappa, u0)

The problem u_t = kappa u_xx + source(x, t) on (0, 1) with Dirichlet values
left(t) and right(t) and initial profile u0(x). The two-argument form has
no source and zero boundary values.
"""
struct HeatProblem{F,S,L,R}
    kappa::Float64
    u0::F
    source::S
    left::L
    right::R
end
HeatProblem(kappa::Real, u0) = HeatProblem(Float64(kappa), u0, (x, t) -> 0.0, t -> 0.0, t -> 0.0)

"""The N interior grid points i / (N + 1)."""
grid(N::Integer) = [i / (N + 1) for i in 1:N]

"""
    second_difference!(d2, u, uL, uR, dx) -> d2

The second difference at every interior point: (u[i-1] - 2u[i] + u[i+1]) /
dx^2, where the neighbours of the first and the last point are the boundary
values uL and uR. Exact (up to rounding) when u is a quadratic in x.
"""
function second_difference!(d2, u, uL, uR, dx)
    error("TODO(hole:second_difference)")
end

"""
    ftcs_step!(unew, u, p::HeatProblem, t, dt, dx, d2) -> unew

One forward-Euler step from time t: unew = u + dt (kappa u_xx + s(x, t)),
with the second difference taken with the boundary values at t and the
source at the grid points x_i = i dx at time t. `d2` is work space of
length N. Stable only for r = kappa dt / dx^2 <= 1/2 (about).
"""
function ftcs_step!(unew, u, p::HeatProblem, t, dt, dx, d2)
    error("TODO(hole:ftcs_step)")
end

"""
    thomas!(x, a, b, c, d) -> x

Solve the tridiagonal system with sub-diagonal a[2:n], diagonal b[1:n] and
super-diagonal c[1:n-1] (a[1] and c[n] are ignored) for the right-hand side
d, by Gaussian elimination without pivoting (the Thomas algorithm): a
forward sweep, then back substitution. O(n) work. `c` and `d` are
overwritten. Stable without pivoting when the matrix is diagonally
dominant, as the heat equation's implicit matrices are.
"""
function thomas!(x, a, b, c, d)
    error("TODO(hole:thomas)")
end

"""Work arrays for theta_step! on N points: the three diagonals, the right-hand side, a second difference."""
struct ThetaWork
    a::Vector{Float64}
    b::Vector{Float64}
    c::Vector{Float64}
    d::Vector{Float64}
    d2::Vector{Float64}
end
ThetaWork(N::Integer) = ThetaWork((zeros(N) for _ in 1:5)...)

"""
    theta_step!(unew, u, p::HeatProblem, t, dt, dx, theta, w::ThetaWork) -> unew

One theta-method step from t to t + dt:

    (unew - u) / dt = theta (kappa L unew + s(t + dt)) + (1 - theta) (kappa L u + s(t)),

where L is the second difference with the boundary values at the new time
for unew and at the old time for u. The unknowns satisfy a tridiagonal
system: diagonal 1 + 2 theta r, off-diagonals -theta r (r = kappa dt /
dx^2), and the boundary values at t + dt move to the right-hand side.
theta = 1 is backward Euler (order 1 in time), theta = 1/2 Crank-Nicolson
(order 2), theta = 0 reproduces ftcs_step!.
"""
function theta_step!(unew, u, p::HeatProblem, t, dt, dx, theta, w::ThetaWork)
    N = length(u)
    r = p.kappa * dt / dx^2
    second_difference!(w.d2, u, p.left(t), p.right(t), dx)
    for i in 1:N
        x = i * dx
        w.a[i] = -theta * r
        w.b[i] = 1 + 2 * theta * r
        w.c[i] = -theta * r
        w.d[i] = u[i] + dt * ((1 - theta) * (p.kappa * w.d2[i] + p.source(x, t)) + theta * p.source(x, t + dt))
    end
    w.d[1] += theta * r * p.left(t + dt)
    w.d[N] += theta * r * p.right(t + dt)
    return thomas!(unew, w.a, w.b, w.c, w.d)
end

"""
    solve_heat(p::HeatProblem, N, nsteps, T; method = :cn) -> (x, u, cost)

Integrate from t = 0 to T in `nsteps` equal steps on N interior points.
`method` is `:ftcs` (ftcs_step!), `:be` (theta = 1) or `:cn` (theta =
1/2). Starts from u0 at the grid points. Returns the grid, the solution at
T and the cost in grid-point updates, N * nsteps. The time of step k is
computed as k * dt (not by adding dt k times), so the last step ends
exactly at T.
"""
function solve_heat(p::HeatProblem, N::Integer, nsteps::Integer, T::Real; method::Symbol = :cn)
    method in (:ftcs, :be, :cn) || throw(ArgumentError("method must be :ftcs, :be or :cn"))
    nsteps >= 1 || throw(ArgumentError("need at least one step"))
    x = grid(N)
    dx = 1 / (N + 1)
    dt = T / nsteps
    u = p.u0.(x)
    unew = similar(u)
    w = ThetaWork(N)
    theta = method === :be ? 1.0 : 0.5
    for k in 0:nsteps-1
        t = k * dt
        if method === :ftcs
            ftcs_step!(unew, u, p, t, dt, dx, w.d2)
        else
            theta_step!(unew, u, p, t, dt, dx, theta, w)
        end
        u, unew = unew, u
    end
    return x, u, N * nsteps
end

"""
    mms_problem(kappa) -> (p::HeatProblem, exact)

A manufactured solution: exact(x, t) = exp(-t) sin(pi x) + x^2 cos(t). The
problem is built so that `exact` solves it: u0 = exact(x, 0), left(t) =
exact(0, t), right(t) = exact(1, t), and the source is what is left over,
s = exact_t - kappa exact_xx. Every term of the scheme (both boundaries,
the source, the time dependence) is exercised, and the error of a solver
against `exact` is the discretization error alone.
"""
function mms_problem(kappa::Real)
    error("TODO(hole:mms_problem)")
end

"""
    fit_order(hs, errs) -> Float64

The observed order of convergence: the least-squares slope of `log(errs)`
against `log(hs)` over all the points given (at least two, all positive).
Which points to pass (the fit range) is the caller's decision.
"""
function fit_order(hs, errs)
    length(hs) == length(errs) >= 2 || throw(ArgumentError("need at least two (h, error) pairs"))
    all(>(0), hs) && all(>(0), errs) || throw(ArgumentError("step sizes and errors must be positive"))
    x = log.(hs)
    y = log.(errs)
    xm, ym = sum(x) / length(x), sum(y) / length(y)
    return sum((x .- xm) .* (y .- ym)) / sum(abs2, x .- xm)
end

end # module Heat1D
