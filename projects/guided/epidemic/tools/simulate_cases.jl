# Generates data/cases.csv (and acceptance/data/cases.csv, the same file) for
# the epidemic project. Run in the diffeq env (container on Windows):
#   ./tutor run projects/guided/epidemic/tools/simulate_cases.jl --env=diffeq --sandbox=docker
# and save the printed CSV. Independent of the reference package on purpose.
#
# Model: SIR with BETA = 0.45, GAMMA = 0.17 per day, (S, I, R) = (0.999, 0.001, 0)
# on day 0, a town of 10 000. The Poisson mean for day k is
# 10 000 * (S(k - 1) - S(k)), from Tsit5 with abstol = reltol = 1e-10; each
# count is a Poisson draw from Xoshiro(SEED), by counting the arrivals of a
# unit-rate Poisson process before time mu (exact for any mu).
using DifferentialEquations, Random

const BETA, GAMMA = 0.45, 0.17
const SEED = 20261109
const DAYS = 50

function rhs!(du, u, p, t)
    b, g = p
    du[1] = -b * u[1] * u[2]
    du[2] = b * u[1] * u[2] - g * u[2]
    du[3] = g * u[2]
    return nothing
end

function poisson(rng, mu)
    k = 0
    t = randexp(rng)
    while t < mu
        k += 1
        t += randexp(rng)
    end
    return k
end

prob = ODEProblem(rhs!, [0.999, 0.001, 0.0], (0.0, Float64(DAYS)), (BETA, GAMMA))
S = Array(solve(prob, Tsit5(); saveat = 0:DAYS, abstol = 1e-10, reltol = 1e-10))[1, :]
mu = 10_000.0 .* (S[1:end-1] .- S[2:end])
rng = Xoshiro(SEED)
println("day,cases")
for (k, m) in enumerate(mu)
    println(k, ",", poisson(rng, m))
end
