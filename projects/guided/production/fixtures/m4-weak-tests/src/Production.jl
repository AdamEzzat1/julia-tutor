# A student's whole project, correct, in a compact style.
module Production

using JuMP, HiGHS, Roots, Optim

export solve_plan, shadow_prices, break_even, best_price

function lp(margin, use, capacity)
    model = Model(HiGHS.Optimizer)
    set_silent(model)
    @variable(model, x[eachindex(margin)] >= 0)
    @constraint(model, c[r in axes(use, 1)], sum(use[r, p] * x[p] for p in eachindex(margin)) <= capacity[r])
    @objective(model, Max, sum(margin .* x))
    optimize!(model)
    termination_status(model) == MOI.OPTIMAL || error("not optimal: $(termination_status(model))")
    return model
end

function solve_plan(margin, use, capacity)
    model = lp(margin, use, capacity)
    return (units = collect(value.(model[:x])), profit = objective_value(model))
end

shadow_prices(margin, use, capacity) = collect(shadow_price.(lp(margin, use, capacity)[:c]))

function break_even(margin, use, capacity; product = 1)
    function g(m)
        mg = float(copy(margin))
        mg[product] = m
        return solve_plan(mg, use, capacity).units[product] - 1e-6   # above the 1e-7 tolerance
    end
    hi = 1.0
    while g(hi) <= 0
        hi > 1e6 && return Inf
        hi = 2hi
    end
    return find_zero(g, (-1.0, hi), Bisection())
end

function best_price(q, cost; p0 = cost + 1)
    f(v) = (cost - v[1]) * q(v[1])   # the negated profit
    r = optimize(f, [Float64(p0)], LBFGS(); autodiff = Optim.ADTypes.AutoForwardDiff())
    return Optim.minimizer(r)[1]
end

best_price(a, b, cost) = best_price(p -> a * exp(-b * p), cost)

end
