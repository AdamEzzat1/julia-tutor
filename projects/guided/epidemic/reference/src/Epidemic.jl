"""
Reference solution of the `epidemic` guided project: an SIR model on
DifferentialEquations.jl, checks it must pass, a Poisson loss against daily
case counts, and a fit of the two rates by golden-section search.
"""
module Epidemic

using DifferentialEquations

export sir!, simulate, peak_day, POPULATION, U0, read_cases, expected_cases, loss, golden_section, fit

# Solver tolerances for every solve in the package (milestone 1 states them).
const TOL = 1e-10

# ---- milestone 1: the model ----------------------------------------------------------------

"""SIR right-hand side in place: u = (S, I, R) as fractions, p = (beta, gamma)."""
function sir!(du, u, p, t)
    beta, gamma = p
    S, I, R = u
    du[1] = -beta * S * I
    du[2] = beta * S * I - gamma * I
    du[3] = gamma * I
    return nothing
end

"""The 3 × length(days) states at `days`, starting from `u0` at day 0."""
function simulate(p, u0, days)
    prob = ODEProblem(sir!, collect(Float64, u0), (0.0, Float64(last(days))), p)
    sol = solve(prob, Tsit5(); saveat = days, abstol = TOL, reltol = TOL)
    return Array(sol)
end

# ---- milestone 2: the peak -------------------------------------------------------------

"""
The time at which I is largest: the root of beta S - gamma (where dI/dt = 0),
found by the solver's event location. 0.0 when I never grows; `horizon` when
it is still growing there.
"""
function peak_day(p, u0; horizon = 365)
    beta, gamma = p
    beta * u0[1] <= gamma && return 0.0
    growth(u, t, integrator) = beta * u[1] - gamma
    cb = ContinuousCallback(growth, terminate!)
    prob = ODEProblem(sir!, collect(Float64, u0), (0.0, Float64(horizon)), p)
    sol = solve(prob, Tsit5(); abstol = TOL, reltol = TOL, callback = cb, save_everystep = false)
    return sol.t[end]
end

# ---- milestone 3: data and a loss ----------------------------------------------------

"""Population size of the outbreak in data/cases.csv."""
const POPULATION = 10_000.0
"""Initial state (S, I, R) on day 0 of the outbreak in data/cases.csv."""
const U0 = [0.999, 0.001, 0.0]

"""Daily counts from a `day,cases` CSV whose days are 1, 2, ..., D in order."""
function read_cases(io::IO)
    lines = [l for l in eachline(io) if !isempty(strip(l))]
    isempty(lines) && throw(ArgumentError("no header line"))
    cases = Int[]
    for (k, line) in enumerate(lines[2:end])   # line 1 is the header
        fields = split(line, ',')
        length(fields) == 2 || throw(ArgumentError("line $(k + 1): expected two fields"))
        day = parse(Int, strip(fields[1]))
        day == k || throw(ArgumentError("expected day $k, got day $day"))
        push!(cases, parse(Int, strip(fields[2])))
    end
    return cases
end

"""Model new cases on days 1..ndays: POPULATION * (S(k - 1) - S(k))."""
function expected_cases(p, ndays::Integer)
    U = simulate(p, U0, 0:ndays)
    S = U[1, :]
    return POPULATION .* (S[1:end-1] .- S[2:end])
end

"""Poisson negative log-likelihood of `cases` given the model, constants dropped."""
function loss(p, cases::AbstractVector{<:Real})
    mu = expected_cases(p, length(cases))
    # log needs mu > 0; rates so extreme that S falls below the solver's
    # tolerance give mu <= 0 and are never the minimum.
    any(<=(0), mu) && return Inf
    return sum(mu .- cases .* log.(mu))
end

# ---- milestone 4: the fit ------------------------------------------------------------

const INVPHI = (sqrt(5) - 1) / 2   # 0.618...: the bracket shrinks by this per evaluation

"""Minimiser of a unimodal `f` on [a, b], to within `tol`; one new evaluation per step."""
function golden_section(f, a, b; tol = 1e-8)
    a, b = float(a), float(b)
    c = b - INVPHI * (b - a)
    d = a + INVPHI * (b - a)
    fc, fd = f(c), f(d)
    while b - a > tol
        if fc < fd
            # the minimum is in [a, d]: the old c becomes the new d
            b, d, fd = d, c, fc
            c = b - INVPHI * (b - a)
            fc = f(c)
        else
            # the minimum is in [c, b]: the old d becomes the new c
            a, c, fc = c, d, fd
            d = a + INVPHI * (b - a)
            fd = f(d)
        end
    end
    return (a + b) / 2
end

"""
Fit (beta, gamma) to daily `cases`: for each gamma in `gamma_grid` the best
beta in `beta_range` by golden-section search; then a golden-section search
over gamma between the grid neighbours of the best grid point.
"""
function fit(cases; beta_range, gamma_grid)
    lo, hi = beta_range
    best_beta(g) = golden_section(b -> loss((b, g), cases), lo, hi; tol = 1e-6)
    profile(g) = loss((best_beta(g), g), cases)
    grid = collect(Float64, gamma_grid)
    k = argmin(map(profile, grid))
    g = golden_section(profile, grid[max(k - 1, 1)], grid[min(k + 1, end)]; tol = 1e-6)
    return (beta = best_beta(g), gamma = g)
end

end # module Epidemic
