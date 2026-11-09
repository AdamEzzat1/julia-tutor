# A student's milestone 2, in another style than the reference: indexing
# instead of unpacking, and the peak found by bisection on the dense solution
# instead of an event callback.
module Epidemic

using DifferentialEquations

export sir!, simulate, peak_day

function sir!(du, u, p, t)
    infection = p[1] * u[1] * u[2]
    recovery = p[2] * u[2]
    du[1] = -infection
    du[2] = infection - recovery
    du[3] = recovery
    return nothing
end

function simulate(p, u0, days)
    prob = ODEProblem(sir!, Float64[u0[1], u0[2], u0[3]], (0.0, Float64(days[end])), p)
    sol = solve(prob, Tsit5(); abstol = 1e-10, reltol = 1e-10, saveat = days)
    return reduce(hcat, sol.u)
end

function peak_day(p, u0; horizon = 365)
    g(S) = p[1] * S - p[2]          # dI/dt = I * g(S)
    g(u0[1]) > 0 || return 0.0
    prob = ODEProblem(sir!, Float64[u0[1], u0[2], u0[3]], (0.0, Float64(horizon)), p)
    sol = solve(prob, Tsit5(); abstol = 1e-10, reltol = 1e-10)
    g(sol(Float64(horizon))[1]) > 0 && return Float64(horizon)
    lo, hi = 0.0, Float64(horizon)
    # g(S(t)) falls with t (S only decreases): bisect to 1e-12 days.
    while hi - lo > 1e-12
        mid = (lo + hi) / 2
        if g(sol(mid)[1]) > 0
            lo = mid
        else
            hi = mid
        end
    end
    return (lo + hi) / 2
end

end
