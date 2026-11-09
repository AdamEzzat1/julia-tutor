"""
    DerivCheck

Reference solution of the `derivcheck` guided project: three ways to get a
gradient (symbolic, forward-mode AD, central differences) and a checker that
says whether a hand-written gradient agrees, and where it is worst.

Every function to differentiate takes one `AbstractVector` and returns a
real number.
"""
module DerivCheck

using Symbolics, ForwardDiff, LinearAlgebra

export symbolic_gradient, ad_gradient, ad_jacobian, central_difference, GradientReport, check_gradient

# ---- milestone 1: symbolic ---------------------------------------------------------

"""
    symbolic_gradient(f, n::Integer) -> Function

Differentiate `f(x)` symbolically for `x` with `n` components and return a
compiled function from a vector to its gradient (a `Vector`).
"""
function symbolic_gradient(f, n::Integer)
    n >= 1 || throw(ArgumentError("n must be at least 1, got $n"))
    x = Symbolics.variables(:x, 1:n)
    g = Symbolics.gradient(f(x), x)
    oop, _ = build_function(g, x; expression = Val(false))
    return oop
end

# ---- milestone 2: forward-mode AD ------------------------------------------------------

"""
    ad_gradient(f, x::AbstractVector) -> Vector

The gradient of `f` at `x` by forward-mode automatic differentiation.
"""
ad_gradient(f, x::AbstractVector) = ForwardDiff.gradient(f, x)

"""
    ad_jacobian(F, x::AbstractVector) -> Matrix

The Jacobian of a vector-valued `F` at `x`: entry (i, j) is dF_i/dx_j, so
the size is (length(F(x)), length(x)).
"""
ad_jacobian(F, x::AbstractVector) = ForwardDiff.jacobian(F, x)

# ---- milestone 3: central differences -------------------------------------------------

# Step choice: the central difference has truncation error ~ h^2 |f'''| / 6 and
# rounding error ~ eps |f| / h. Balancing them gives h ~ cbrt(eps), and the
# total relative error ~ eps^(2/3) ≈ 4e-11 for well-scaled f.
const DEFAULT_H = cbrt(eps(Float64))

"""
    central_difference(f, x::AbstractVector; h = cbrt(eps(Float64))) -> Vector{Float64}

The gradient of `f` at `x` by central differences, component by component,
with step `h * max(1, abs(x[i]))` (relative to the size of `x[i]`). `x` is
not changed.
"""
function central_difference(f, x::AbstractVector; h::Real = DEFAULT_H)
    g = zeros(Float64, length(x))
    xp = Vector{Float64}(x)
    for i in eachindex(xp)
        xi = xp[i]
        step = h * max(one(xi), abs(xi))
        xp[i] = xi + step
        fp = f(xp)
        xp[i] = xi - step
        fm = f(xp)
        xp[i] = xi
        g[i] = (fp - fm) / (2step)
    end
    return g
end

# ---- milestone 4: the checker ---------------------------------------------------------

"""
Result of `check_gradient`: whether every point agreed within `rtol`, the
point where the relative error was largest, and that error.
"""
struct GradientReport
    ok::Bool
    worst_point::Vector{Float64}
    worst_error::Float64
end

"""
    relative_error(g, ref) -> Float64

`norm(g - ref) / max(norm(ref), 1)`: relative for large gradients, absolute
near a zero gradient (where a relative error would divide by zero).
"""
relative_error(g, ref) = norm(g - ref) / max(norm(ref), one(norm(ref)))

"""
    check_gradient(f, grad, points; rtol = 1e-8) -> GradientReport

Compare the hand-written gradient `grad(x)` with `ad_gradient(f, x)` at every
point. `ok` is true when the largest relative error is at most `rtol`.
"""
function check_gradient(f, grad, points; rtol::Real = 1e-8)
    isempty(points) && throw(ArgumentError("check_gradient needs at least one point"))
    worst = -Inf
    worst_x = Float64[]
    for x in points
        e = relative_error(grad(x), ad_gradient(f, x))
        isnan(e) && (e = Inf)     # a NaN gradient is never "close"
        if e > worst
            worst, worst_x = e, Vector{Float64}(x)
        end
    end
    return GradientReport(worst <= rtol, worst_x, worst)
end

end # module DerivCheck
