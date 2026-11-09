# A student's milestone 1 in another style: the constraints as one vector
# inequality and JuMP's combined status check.
module Production

using JuMP
import HiGHS

export solve_plan

function solve_plan(margin::AbstractVector, use::AbstractMatrix, capacity::AbstractVector)
    model = Model(HiGHS.Optimizer)
    set_silent(model)
    n = size(use, 2)
    @variable(model, units[1:n] >= 0)
    @constraint(model, use * units .<= capacity)
    @objective(model, Max, margin' * units)
    optimize!(model)
    if !is_solved_and_feasible(model)
        error("no optimal plan: $(termination_status(model))")
    end
    return (units = value.(units), profit = objective_value(model))
end

end
