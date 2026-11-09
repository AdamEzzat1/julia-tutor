# A student's milestones 1-3: right up to the bracket, which is fixed at
# [0, 100], so a product whose break-even margin is above 100 is reported
# as never made.
module Production

using JuMP, HiGHS, Roots

export solve_plan, shadow_prices, break_even

function plan(margin, use, capacity)
    model = Model(HiGHS.Optimizer)
    set_silent(model)
    @variable(model, x[1:length(margin)] >= 0)
    @constraint(model, res, use * x .<= capacity)
    @objective(model, Max, margin' * x)
    optimize!(model)
    termination_status(model) == MOI.OPTIMAL || error("solver: $(termination_status(model))")
    return model
end

function solve_plan(margin, use, capacity)
    model = plan(margin, use, capacity)
    return (units = value.(model[:x]), profit = objective_value(model))
end

shadow_prices(margin, use, capacity) = shadow_price.(plan(margin, use, capacity)[:res])

function break_even(margin, use, capacity; product = 1)
    # Made means more than 1e-6 units: above HiGHS's 1e-7 feasibility tolerance.
    function made_minus(m)
        mg = Float64.(margin)
        mg[product] = m
        return solve_plan(mg, use, capacity).units[product] - 1e-6
    end
    made_minus(100.0) > 0 || return Inf
    return find_zero(made_minus, (0.0, 100.0), Bisection())
end

end
