"""
    DualAD

Forward-mode automatic differentiation with dual numbers, written from
scratch, and central differences to compare it with.

A dual number `Dual(v, d)` carries a value `v` and a derivative part `d`,
read as v + d*eps with eps^2 = 0. Every operation applies its derivative
rule to `d`, so evaluating ordinary Julia code on `Dual(x, 1.0)` gives
f(x) and f'(x) together, exact up to the rounding of each operation. No
step size is involved, which is the difference from finite differences.

Dispatch does the work: `Dual <: Real`, the arithmetic and elementary
functions have `Dual` methods, and promotion turns `2 * d` into a product
of two duals. Generic code written for `Real` then differentiates without
change.

Not handled (said plainly): nested derivatives of closures that capture an
outer dual (perturbation confusion; ForwardDiff.jl solves it with tags),
branches on the derivative part, and functions without a `Dual` method.
"""
module DualAD

export Dual, value, partial, lift, derivative, gradient, central_diff, fit_order, babylonian_sqrt

"""
    Dual(v, d)

A dual number: value `v`, derivative part `d`, both of type `T`. Mixed
argument types are promoted (`Dual(1, 2.0) isa Dual{Float64}`).
"""
struct Dual{T<:Real} <: Real
    v::T
    d::T
end
Dual(v::Real, d::Real) = Dual(promote(v, d)...)

"""`value(x)`: the value part of a dual; a plain number is its own value."""
value(x::Dual) = x.v
value(x::Real) = x
"""`partial(x)`: the derivative part of a dual; a plain number has derivative 0."""
partial(x::Dual) = x.d
partial(x::Real) = zero(x)

# ---- promotion: plain numbers are duals with derivative 0 -----------------------------------

Base.convert(::Type{Dual{T}}, x::Dual{T}) where {T} = x
Base.convert(::Type{Dual{T}}, x::Dual) where {T} = Dual{T}(convert(T, x.v), convert(T, x.d))
Base.convert(::Type{Dual{T}}, x::Real) where {T} = Dual{T}(convert(T, x), zero(T))
Base.promote_rule(::Type{Dual{T}}, ::Type{Dual{S}}) where {T,S} = Dual{promote_type(T, S)}
Base.promote_rule(::Type{Dual{T}}, ::Type{S}) where {T,S<:Real} = Dual{promote_type(T, S)}
Base.float(x::Dual) = Dual(float(x.v), float(x.d))

# ---- comparison and hashing look at the value only ---------------------------------------------
#
# Code such as `x < 0 ? -x : x` must take the same branch for a dual as for
# its value, so comparisons ignore the derivative part. `hash` agrees with
# `==` (equal values, equal hashes).

Base.:(==)(a::Dual, b::Dual) = a.v == b.v
Base.:<(a::Dual, b::Dual) = a.v < b.v
Base.:<=(a::Dual, b::Dual) = a.v <= b.v
Base.isless(a::Dual, b::Dual) = isless(a.v, b.v)
Base.hash(a::Dual, h::UInt) = hash(a.v, h)
Base.isfinite(a::Dual) = isfinite(a.v) && isfinite(a.d)
Base.isnan(a::Dual) = isnan(a.v) || isnan(a.d)
Base.show(io::IO, a::Dual) = print(io, "Dual(", a.v, ", ", a.d, ")")

# ---- arithmetic ----------------------------------------------------------------------------

Base.:+(a::Dual, b::Dual) = Dual(a.v + b.v, a.d + b.d)
Base.:-(a::Dual, b::Dual) = Dual(a.v - b.v, a.d - b.d)
Base.:-(a::Dual) = Dual(-a.v, -a.d)
Base.abs(a::Dual) = a.v < 0 ? -a : a

# HOLE: mul
"""
    *(a::Dual, b::Dual) -> Dual

The product rule: (u v)' = u' v + u v'. With a = Dual(u, u') and
b = Dual(v, v'), the value part is u * v.
"""
function Base.:*(a::Dual, b::Dual)
    return Dual(a.v * b.v, a.d * b.v + a.v * b.d)
end

# HOLE: div
"""
    /(a::Dual, b::Dual) -> Dual

The quotient rule: (u / v)' = (u' v - u v') / v^2. The value part is
u / v; dividing by a dual whose value is 0 gives what Float64 division
gives (Inf or NaN), not an error.
"""
function Base.:/(a::Dual, b::Dual)
    return Dual(a.v / b.v, (a.d * b.v - a.v * b.d) / (b.v * b.v))
end

# HOLE: chain
"""
    lift(f, df, x::Dual) -> Dual

The chain rule for a function of one variable: given `f` and its
derivative `df` (both as functions of a plain number), the value part is
f(v) and the derivative part is f'(v) times x's derivative part. Every
elementary function below is defined with it, so sin(2x) at Dual(x, 1)
carries 2 cos(2x).
"""
function lift(f, df, x::Dual)
    return Dual(f(x.v), df(x.v) * x.d)
end

Base.sin(x::Dual) = lift(sin, cos, x)
Base.cos(x::Dual) = lift(cos, t -> -sin(t), x)
Base.exp(x::Dual) = lift(exp, exp, x)
Base.log(x::Dual) = lift(log, inv, x)
Base.sqrt(x::Dual) = lift(sqrt, t -> inv(2 * sqrt(t)), x)

# HOLE: power
"""
    ^(x::Dual, n::Integer) -> Dual

The power rule: (u^n)' = n u^(n-1) u'. For n = 0 the result is the
constant 1 with derivative 0, also at u = 0 (where n u^(n-1) would be
0 * Inf = NaN). Negative n works wherever u != 0.
"""
function Base.:^(x::Dual, n::Integer)
    n == 0 && return Dual(one(x.v), zero(x.d))
    return Dual(x.v^n, n * x.v^(n - 1) * x.d)
end

# ---- derivatives -----------------------------------------------------------------------------

# HOLE: derivative
"""
    derivative(f, x::Real) -> Real

f'(x) by one evaluation of `f` on the dual number x + 1*eps (the seed 1
says "differentiate with respect to x"). `x` is converted to floating point
first. If `f` returns a plain number (a constant function), the derivative
is 0.
"""
function derivative(f, x::Real)
    xf = float(x)
    return partial(f(Dual(xf, one(xf))))
end

# HOLE: gradient
"""
    gradient(f, x::AbstractVector{<:Real}) -> Vector

The gradient of a scalar function of a vector, by forward mode: one
evaluation of `f` per component i, on the vector whose j-th entry is
Dual(x[j], 1 if j == i else 0). Costs `length(x)` evaluations, each on
duals. The result has x's floating-point element type.
"""
function gradient(f, x::AbstractVector{<:Real})
    xf = float.(x)
    g = similar(xf)
    for i in eachindex(xf)
        xd = [Dual(xf[j], j == i ? one(xf[j]) : zero(xf[j])) for j in eachindex(xf)]
        g[i] = partial(f(xd))
    end
    return g
end

# HOLE: central_diff
"""
    central_diff(f, x, h) -> Float64

The central difference (f(x + h) - f(x - h)) / (2h): two evaluations of
`f`, truncation error h^2 |f'''| / 6, and a rounding error that grows like
eps |f| / h as h shrinks. The best h balances the two.
"""
function central_diff(f, x::Real, h::Real)
    return (f(x + h) - f(x - h)) / (2 * h)
end

# HOLE: fit_order
"""
    fit_order(hs, errs) -> Float64

The observed order of convergence: the least-squares slope of `log(errs)`
against `log(hs)` over all the points given (at least two, all positive).
For errors that behave like `C * h^p` the slope is `p`; for a rounding
error like `C / h` it is -1. Which points to pass (the fit range) is the
caller's decision.
"""
function fit_order(hs, errs)
    length(hs) == length(errs) >= 2 || throw(ArgumentError("need at least two (h, error) pairs"))
    all(>(0), hs) && all(>(0), errs) || throw(ArgumentError("step sizes and errors must be positive"))
    x = log.(hs)
    y = log.(errs)
    xm, ym = sum(x) / length(x), sum(y) / length(y)
    return sum((x .- xm) .* (y .- ym)) / sum(abs2, x .- xm)
end

# ---- an algorithm to differentiate -----------------------------------------------------------

"""
    babylonian_sqrt(a; iters = 6, x0 = 1) -> same type as a

sqrt(a) by `iters` Babylonian (Newton) steps x <- (x + a / x) / 2 from
`x0`. Plain generic code: on a dual it returns the derivative of the
*algorithm*, which approaches 1 / (2 sqrt(a)) only as the iteration
converges.
"""
function babylonian_sqrt(a::Real; iters::Integer = 6, x0::Real = 1)
    x = one(a) * x0
    for _ in 1:iters
        x = (x + a / x) / 2
    end
    return x
end

end # module DualAD
