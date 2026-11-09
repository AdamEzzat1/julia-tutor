# A student's milestones 1-3 in another style: `using ... :` imports, a
# comprehension for the differences, `float` instead of a typed copy.
module DerivCheck

using Symbolics: Symbolics, build_function
import ForwardDiff

export symbolic_gradient, ad_gradient, ad_jacobian, central_difference

function symbolic_gradient(f, n::Integer)
    if n < 1
        throw(ArgumentError("need at least one variable"))
    end
    vars = Symbolics.variables(:x, 1:n)
    grad_expr = Symbolics.gradient(f(vars), vars)
    funcs = build_function(grad_expr, vars; expression = Val(false))
    return first(funcs)
end

ad_gradient(f, x::AbstractVector) = ForwardDiff.gradient(f, x)
ad_jacobian(F, x::AbstractVector) = ForwardDiff.jacobian(F, x)

# Truncation ~ s^2 |f'''| / 6, rounding ~ eps |f| / s: balanced at s ~ cbrt(eps), relative to |x_i|.
function central_difference(f, x::AbstractVector; h::Real = cbrt(eps(Float64)))
    y = float(collect(x))
    function partial(i)
        s = h
        e = zeros(length(y))
        e[i] = s
        return (f(y + e) - f(y - e)) / (2s)
    end
    return [partial(i) for i in eachindex(y)]
end

end
