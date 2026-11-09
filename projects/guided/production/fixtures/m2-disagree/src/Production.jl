# A student's milestones 1-2 that reads the raw duals (solver sign
# convention: <= 0 here) instead of the shadow prices.
module Production

using JuMP, HiGHS

export solve_plan, shadow_prices

function build(margin, use, capacity)
    model = Model(HiGHS.Optimizer)
    set_silent(model)
    np = length(margin)
    @variable(model, x[1:np] >= 0)
    cons = [@constraint(model, sum(use[r, p] * x[p] for p in 1:np) <= capacity[r]) for r in axes(use, 1)]
    @objective(model, Max, sum(margin[p] * x[p] for p in 1:np))
    optimize!(model)
    is_solved_and_feasible(model) || error("no optimum: ", termination_status(model))
    return model, x, cons
end

function solve_plan(margin, use, capacity)
    model, x, _ = build(margin, use, capacity)
    return (units = value.(x), profit = objective_value(model))
end

function shadow_prices(margin, use, capacity)
    _, _, cons = build(margin, use, capacity)
    return dual.(cons)
end

end
