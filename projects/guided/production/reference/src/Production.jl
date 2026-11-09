"""
    Production

Reference solution of the `production` guided project: a weekly production
plan as a linear program (JuMP and HiGHS), the shadow price of each resource,
the break-even margin at which a product enters the plan (Roots.jl), and a
price chosen against a demand curve (Optim.jl with ForwardDiff gradients).

Data layout throughout: `margin[p]` is the profit per unit of product `p`,
`use[r, p]` the amount of resource `r` one unit of product `p` needs, and
`capacity[r]` how much of resource `r` there is per week.
"""
module Production

using JuMP, HiGHS, Roots, Optim, ForwardDiff

export solve_plan, shadow_prices, break_even, best_price

# ---- milestone 1: the linear program ------------------------------------------------

"""
    plan_model(margin, use, capacity) -> (model, x, cons)

The LP: maximise margin' x subject to use * x <= capacity and x >= 0, with
a silent HiGHS. `cons[r]` is the constraint of resource `r`.
"""
function plan_model(margin::AbstractVector, use::AbstractMatrix, capacity::AbstractVector)
    nr, np = size(use)
    length(margin) == np || throw(DimensionMismatch("margin has $(length(margin)) entries for $np products"))
    length(capacity) == nr || throw(DimensionMismatch("capacity has $(length(capacity)) entries for $nr resources"))
    model = Model(HiGHS.Optimizer)
    set_silent(model)
    @variable(model, x[1:np] >= 0)
    @constraint(model, cons[r = 1:nr], sum(use[r, p] * x[p] for p in 1:np) <= capacity[r])
    @objective(model, Max, sum(margin[p] * x[p] for p in 1:np))
    optimize!(model)
    st = termination_status(model)
    st == MOI.OPTIMAL || error("the plan has no optimum: the solver reports $st")
    return model, x, cons
end

"""
    solve_plan(margin::Vector, use::Matrix, capacity::Vector) -> NamedTuple{(:units, :profit)}

The optimal weekly plan: `units[p]` of each product and the total profit.
Throws an `ErrorException` when the solver does not report an optimum (an
unbounded or infeasible plan).
"""
function solve_plan(margin::AbstractVector, use::AbstractMatrix, capacity::AbstractVector)
    model, x, _ = plan_model(margin, use, capacity)
    return (units = value.(x), profit = objective_value(model))
end

# ---- milestone 2: shadow prices -------------------------------------------------------

"""
    shadow_prices(margin, use, capacity) -> Vector{Float64}

Profit gained per extra unit of each resource at the optimal plan (the dual
values, sign-normalised by JuMP so that they are nonnegative here). A
resource that is not used up has price 0.
"""
function shadow_prices(margin::AbstractVector, use::AbstractMatrix, capacity::AbstractVector)
    _, _, cons = plan_model(margin, use, capacity)
    return [shadow_price(c) for c in cons]
end

# ---- milestone 3: break-even margin -----------------------------------------------------

# A product counts as made when its units exceed this. HiGHS's primal
# feasibility tolerance is 1e-7, so a product that is not made can show up
# to about 1e-7 units; a made product sits at a vertex of size ~1 or more.
const MADE = 1e-6

# Doubling the upper end of the bracket stops here: a product that is not
# made even at this margin needs a resource there is none of.
const MAX_MARGIN = 1e6

"""
    break_even(margin, use, capacity; product = 1) -> Float64

The smallest margin of `product` at which the optimal plan makes it (the
other margins as given), found by bisection on units(m) - MADE. `Inf` when
the product is not made at any margin up to 1e6.
"""
function break_even(margin::AbstractVector, use::AbstractMatrix, capacity::AbstractVector; product::Integer = 1)
    function excess(m)
        mg = float.(collect(margin))
        mg[product] = m
        return solve_plan(mg, use, capacity).units[product] - MADE
    end
    # At a negative margin the product is never made (use >= 0, so dropping it
    # keeps the plan feasible and raises the profit): -1 is a safe low end.
    lo = -1.0
    hi = 1.0
    while excess(hi) <= 0
        hi > MAX_MARGIN && return Inf
        hi *= 2
    end
    return find_zero(excess, (lo, hi), Bisection())
end

# ---- milestone 4: pricing against demand -------------------------------------------------

"""
    best_price(q, cost; p0 = cost + 1) -> Float64

The price `p` that maximises (p - cost) * q(p) for a demand curve `q`,
found by LBFGS from `p0` with ForwardDiff gradients (so `q` must accept any
real number type, as generic Julia code does).
"""
function best_price(q, cost::Real; p0::Real = cost + 1)
    negprofit(v) = -(v[1] - cost) * q(v[1])
    res = optimize(negprofit, [float(p0)], LBFGS(); autodiff = Optim.ADTypes.AutoForwardDiff())
    Optim.converged(res) || error("the price search did not converge")
    return Optim.minimizer(res)[1]
end

"""
    best_price(a, b, cost) -> Float64

The best price against the exponential demand q(p) = a exp(-b p).
"""
best_price(a::Real, b::Real, cost::Real) = best_price(p -> a * exp(-b * p), cost)

end # module Production
