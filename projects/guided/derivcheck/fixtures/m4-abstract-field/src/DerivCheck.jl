# A student's full package whose report struct has abstract field types.
module DerivCheck

using Symbolics, ForwardDiff, LinearAlgebra

export symbolic_gradient, ad_gradient, ad_jacobian, central_difference, GradientReport, check_gradient

function symbolic_gradient(f, n::Integer)
    n >= 1 || throw(ArgumentError("n must be positive"))
    x = Symbolics.variables(:x, 1:n)
    return build_function(Symbolics.gradient(f(x), x), x; expression = Val(false))[1]
end

ad_gradient(f, x::AbstractVector) = ForwardDiff.gradient(f, x)
ad_jacobian(F, x::AbstractVector) = ForwardDiff.jacobian(F, x)

function central_difference(f, x::AbstractVector; h::Real = cbrt(eps(Float64)))
    y = Vector{Float64}(x)
    g = similar(y)
    for i in eachindex(y)
        s = h * max(1.0, abs(y[i]))
        yi = y[i]
        y[i] = yi + s; a = f(y)
        y[i] = yi - s; b = f(y)
        y[i] = yi
        g[i] = (a - b) / (2s)
    end
    return g
end

struct GradientReport
    ok::Bool
    worst_point::AbstractVector
    worst_error::Real
end

function check_gradient(f, grad, points; rtol::Real = 1e-8)
    isempty(points) && throw(ArgumentError("no points"))
    errs = map(points) do x
        ref = ad_gradient(f, x)
        e = norm(grad(x) - ref) / max(norm(ref), 1.0)
        isnan(e) ? Inf : e
    end
    k = argmax(errs)
    return GradientReport(errs[k] <= rtol, Vector{Float64}(points[k]), errs[k])
end

end
