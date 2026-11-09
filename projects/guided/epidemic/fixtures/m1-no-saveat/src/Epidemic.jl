# Wrong code: simulate returns the solver's own steps, not the requested days.
module Epidemic

using DifferentialEquations

export sir!, simulate

function sir!(du, u, p, t)
    beta, gamma = p
    S, I, R = u
    du[1] = -beta * S * I
    du[2] = beta * S * I - gamma * I
    du[3] = gamma * I
    return nothing
end

function simulate(p, u0, days)
    prob = ODEProblem(sir!, collect(Float64, u0), (0.0, Float64(last(days))), p)
    sol = solve(prob, Tsit5(); abstol = 1e-10, reltol = 1e-10)
    return Array(sol)
end

end
