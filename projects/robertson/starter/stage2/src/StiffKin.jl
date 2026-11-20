"""
    StiffKin

Stiff chemical kinetics, written from scratch: Robertson's three-species
reaction (Robertson 1966), an explicit and a linearly implicit integrator,
and one adaptive step-size controller for both.

    A -> B         rate k1 = 0.04
    B + B -> C + B rate k2 = 3e7
    B + C -> A + C rate k3 = 1e4

    y1' = -k1 y1 + k3 y2 y3
    y2' =  k1 y1 - k3 y2 y3 - k2 y2^2
    y3' =  k2 y2^2

The total y1 + y2 + y3 is conserved. B lives on a time scale of about
1 / (k3 y3 + 2 k2 y2), a few times 1e-4, while A and C change on a scale of
tens: the problem is stiff.

Methods: Bogacki-Shampine 3(2) (explicit, 4 right-hand-side evaluations a
step, no FSAL here) and the Rosenbrock method ROS2 (2 evaluations, one
Jacobian and two linear solves a step, L-stable). Every step returns the
work it did, so the cases can compare methods by measured cost.
"""
module StiffKin

export Kinetics, ROBERTSON, rhs, jacobian, solve_pivot, bs32_step, ros2_step, Stats, integrate, fit_order

"""
    Kinetics(k1, k2, k3)

The rate constants of Robertson's reactions (see the module docstring).
"""
struct Kinetics
    k1::Float64
    k2::Float64
    k3::Float64
end

"""Robertson's rate constants: k1 = 0.04, k2 = 3e7, k3 = 1e4."""
const ROBERTSON = Kinetics(0.04, 3e7, 1e4)

"""
    rhs(y, p::Kinetics) -> Vector{Float64}

The right-hand side of Robertson's equations at the concentrations
`y = [y1, y2, y3]`:

    y1' = -k1 y1 + k3 y2 y3
    y2' =  k1 y1 - k3 y2 y3 - k2 y2^2
    y3' =  k2 y2^2

The three components sum to zero (up to rounding): mass is conserved.
"""
function rhs(y::AbstractVector, p::Kinetics)
    error("TODO(hole:rhs)")
end

"""
    jacobian(y, p::Kinetics) -> Matrix{Float64}

The 3x3 matrix J[i, j] = d rhs_i / d y_j at `y`. Each column sums to zero,
because the components of rhs do.
"""
function jacobian(y::AbstractVector, p::Kinetics)
    error("TODO(hole:jacobian)")
end

"""
    solve_pivot(A, b) -> Vector{Float64}

The solution x of A x = b by Gaussian elimination with partial pivoting:
at step k the row with the largest |A[i, k]|, i >= k, becomes the pivot
row. Neither A nor b is modified. A zero pivot (a singular matrix) is an
ArgumentError.
"""
function solve_pivot(A::AbstractMatrix, b::AbstractVector)
    error("TODO(hole:solve_pivot)")
end

"""
    bs32_step(f, y, h) -> (ynew, err, nf)

One Bogacki-Shampine 3(2) step of length `h` for the autonomous system
y' = f(y):

    k1 = f(y)
    k2 = f(y + h/2 k1)
    k3 = f(y + 3h/4 k2)
    ynew = y + h (2/9 k1 + 1/3 k2 + 4/9 k3)            (order 3)
    k4 = f(ynew)
    z = y + h (7/24 k1 + 1/4 k2 + 1/3 k3 + 1/8 k4)     (order 2)

`err = ynew - z` is the error estimate (of order h^3); `nf` = 4 is the
number of evaluations of f.
"""
function bs32_step(f, y::AbstractVector, h::Real)
    error("TODO(hole:bs32_step)")
end

"""The ROS2 parameter gamma = 1 + 1/sqrt(2), which makes the method L-stable."""
const GAMMA = 1 + 1 / sqrt(2)

"""
    ros2_step(f, jac, y, h) -> (ynew, err, nf, nj)

One step of the Rosenbrock method ROS2 (Verwer et al. 1999) for y' = f(y),
with W = I - gamma h J, J = jac(y), gamma = GAMMA:

    W k1 = f(y)
    W k2 = f(y + h k1) - 2 k1
    ynew = y + 3h/2 k1 + h/2 k2                        (order 2)

The embedded first-order solution is y + h k1, so `err = ynew - (y + h k1)`
(of order h^2). Each linear system is solved with `solve_pivot`. `nf` = 2
evaluations of f and `nj` = 1 Jacobian.
"""
function ros2_step(f, jac, y::AbstractVector, h::Real)
    error("TODO(hole:ros2_step)")
end

"""
    Stats

The work an integration did: accepted `steps`, `rejected` steps, `nf`
evaluations of f, `nj` Jacobians, `ymin`, the smallest component of any
accepted solution (a negative concentration shows up here), and `t`, the
time reached (T, unless the step size underflowed first).
"""
mutable struct Stats
    steps::Int
    rejected::Int
    nf::Int
    nj::Int
    ymin::Float64
    t::Float64
end
Stats() = Stats(0, 0, 0, 0, Inf, 0.0)

"""
    integrate(step, y0, T; rtol, atol, h0, order, maxsteps = 10^7) -> (y, stats)

Integrate from t = 0 to exactly t = T with an adaptive step. `step(y, h)`
returns `(ynew, err, nf)` or `(ynew, err, nf, nj)`; `order` is the order of
`err` in h (3 for bs32_step, 2 for ros2_step).

A step is accepted when the scaled error

    e = sqrt(mean((err_i / (atol + rtol max(|y_i|, |ynew_i|)))^2))

is at most 1. After every attempt, accepted or not, the next step is
h * min(5, max(0.2, 0.9 e^(-1/order))) (5 if e = 0; a NaN or infinite e,
from a step that blew up, is rejected and the step divided by 5). The last step is
shortened to land on T. Every attempt's evaluations are counted in the
returned `Stats`. If the step falls below 4 eps(max(|t|, 1)) the
integration stops there: the returned y is the last accepted one and
`stats.t < T` says how far it got. More than `maxsteps` attempts is an
error.
"""
function integrate(step, y0::AbstractVector, T::Real; rtol::Real, atol::Real, h0::Real, order::Integer,
                   maxsteps::Integer = 10^7)
    error("TODO(hole:integrate)")
end

"""
    fit_order(hs, errs) -> Float64

The least-squares slope of log(errs) against log(hs): the observed order
of convergence over every point.
"""
function fit_order(hs::AbstractVector, errs::AbstractVector)
    error("TODO(hole:fit_order)")
end

end # module
