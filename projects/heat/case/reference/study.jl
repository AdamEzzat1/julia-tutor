# The heat case study (milestone 3), reference version.
#
# Loaded by the case checker into a module where your package is `Heat1D`.
# Every value `study()` returns can be quoted in report.qmd with a
# `{claim:<id>}` tag; the checker re-runs this file in a fresh process twice
# and compares. Nothing here may be random or read a clock.

using Heat1D

# ---- the operating point of the question ------------------------------------------------------

const KAPPA = 1.0          # diffusivity
const TFINAL = 0.01        # the time the midpoint temperature is needed at
const TARGET = 1e-5        # required relative error of the midpoint temperature
const NFINE = 2^14         # time steps of the fine reference run (time error ~1e-10 relative)
const NS = [2^k - 1 for k in 4:11]          # the space grids tried: 15 ... 2047 interior points
const STEPS = [2^j for j in 0:20]           # the time-step counts tried for the implicit methods

"""The smooth initial profile of the question: u0 = sin(pi x)."""
smooth() = HeatProblem(KAPPA, x -> sinpi(x))

"""
The rough initial profile of the perturbed assumption: 1 on (1/4, 3/4), 0
outside, and 1/2 at the two jumps (the mean of the two sides, which keeps
the grid representation second-order accurate when the jumps are grid
points: every grid here has N + 1 a power of 2).
"""
tophat() = HeatProblem(KAPPA, x -> (0.25 < x < 0.75) ? 1.0 : (x == 0.25 || x == 0.75) ? 0.5 : 0.0)

"""
    exact_mid(ic) -> Float64

The exact midpoint temperature at TFINAL, from the Fourier series of the
initial profile: sum over k of b_k exp(-k^2 pi^2 kappa T) sin(k pi / 2).
For sin(pi x) only b_1 = 1. For the top hat b_k = 2 (cos(k pi/4) -
cos(3 k pi/4)) / (k pi); the terms fall like exp(-0.0987 k^2) at T =
0.01, so the sum is exact to rounding from k = 20 on (exp(-39) < 1e-17);
40 terms are used.
"""
function exact_mid(ic::Symbol)
    ic === :smooth && return exp(-pi^2 * KAPPA * TFINAL)
    s = 0.0
    for k in 1:40
        bk = 2 * (cospi(k / 4) - cospi(3k / 4)) / (k * pi)
        s += bk * exp(-k^2 * pi^2 * KAPPA * TFINAL) * sinpi(k / 2)
    end
    return s
end

problem(ic::Symbol) = ic === :smooth ? smooth() : tophat()

"""The midpoint temperature (N odd, so the midpoint is grid point (N + 1) / 2) and the cost."""
function midpoint(ic::Symbol, N, nsteps, method)
    _, u, cost = solve_heat(problem(ic), N, nsteps, TFINAL; method = method)
    return u[(N + 1) ÷ 2], cost
end

"""FTCS's step count at its stability limit r = 1/2 (rounded up, so r <= 1/2)."""
ftcs_steps(N) = ceil(Int, TFINAL * KAPPA / (0.5 / (N + 1)^2))

"""
    space_error(ic, N) -> Float64

The relative error of the midpoint temperature due to the space grid
alone: Crank-Nicolson with NFINE time steps (time error far below the
budget) against the exact value.
"""
space_error(ic::Symbol, N) = abs(midpoint(ic, N, NFINE, :cn)[1] - exact_mid(ic)) / abs(exact_mid(ic))

"""
    time_error(ic, N, nsteps, method) -> Float64

The relative error due to the time stepping alone: the method with
`nsteps` steps against the fine run on the same grid.
"""
function time_error(ic::Symbol, N, nsteps, method)
    ref = midpoint(ic, N, NFINE, :cn)[1]
    return abs(midpoint(ic, N, nsteps, method)[1] - ref) / abs(exact_mid(ic))
end

"""
    cheapest(ic, method) -> (N, nsteps, cost, space_err, time_err)

The error budget is split: the space error and the time error must each be
at most TARGET / 2. Their sum then meets TARGET whatever their signs. (A
single run's total error cannot be trusted: the two errors have opposite
signs here and can cancel at one setting and not at its neighbours.) N is
the first grid in NS that meets the space half; then the first step count
that meets the time half: STEPS for :be and :cn, the stability limit for
:ftcs (raised by doubling if that is not accurate enough).
"""
function cheapest(ic::Symbol, method::Symbol)
    i = findfirst(N -> space_error(ic, N) <= TARGET / 2, NS)
    i === nothing && error("no grid in NS meets the space budget")
    N = NS[i]
    se = space_error(ic, N)
    candidates = method === :ftcs ? [ftcs_steps(N) * 2^j for j in 0:20] : STEPS
    for ns in candidates
        te = time_error(ic, N, ns, method)
        te <= TARGET / 2 && return (N, ns, N * ns, se, te)
    end
    error("no step count meets the time budget for $method")
end

"""
    stability_limit(N; nsteps = 200) -> Float64

The largest r = kappa dt / dx^2 at which FTCS does not amplify the grid's
fastest mode, sin(N pi x_i), found by bisection on r to 1e-7: a run of
`nsteps` steps grows that mode exactly when |1 - 4 r sin^2(N pi dx / 2)| > 1.
"""
function stability_limit(N::Integer; nsteps::Integer = 200)
    dx = 1 / (N + 1)
    lo, hi = 0.25, 1.0
    while hi - lo > 1e-7
        r = (lo + hi) / 2
        dt = r * dx^2 / KAPPA
        p = HeatProblem(KAPPA, x -> sinpi(N * x))
        _, u, _ = solve_heat(p, N, nsteps, nsteps * dt; method = :ftcs)
        u0 = sinpi.(N .* grid(N))
        maximum(abs, u) > maximum(abs, u0) ? (hi = r) : (lo = r)
    end
    return (lo + hi) / 2
end

"""
The number of strict local maxima of a profile (a plateau counts once),
with the boundary values 0 outside both ends.
"""
function local_maxima(u)
    v = [0.0; u; 0.0]
    n = 0
    i = 2
    while i < length(v)
        j = i
        while j < length(v) - 1 && v[j+1] == v[i]
            j += 1                         # walk over a plateau
        end
        v[i] > v[i-1] && v[j] > v[j+1] && (n += 1)
        i = j + 1
    end
    return n
end

function study()
    out = Dict{String,Any}()
    out["kappa"], out["t_final"], out["target"] = KAPPA, TFINAL, TARGET
    out["exact_mid"] = exact_mid(:smooth)

    # ---- the question: cheapest setting per method, error budget split -----------------------------
    Nf, nsf, cf, se, tef = cheapest(:smooth, :ftcs)
    Nb, nsb, cb, _, teb = cheapest(:smooth, :be)
    Nc, nsc, cc, _, tec = cheapest(:smooth, :cn)
    out["n_space"], out["space_err"] = Nc, se
    out["ns_ftcs"], out["cost_ftcs"], out["time_err_ftcs"] = nsf, cf, tef
    out["ns_be"], out["cost_be"] = nsb, cb
    out["ns_cn"], out["cost_cn"], out["time_err_cn"] = nsc, cc, tec
    costs = Dict("ftcs" => cf, "be" => cb, "cn" => cc)
    out["choice"] = first(sort!(collect(keys(costs)); by = k -> (costs[k], k)))
    out["cost_ratio"] = cf / cc
    # The cancellation that makes a single total error untrustworthy: on a
    # grid too coarse for the space budget, the step count whose total
    # error is smallest, with that total and the space error it hides.
    cN = 31
    tot(ns) = abs(midpoint(:smooth, cN, ns, :cn)[1] - exact_mid(:smooth)) / exact_mid(:smooth)
    cns = STEPS[argmin([tot(ns) for ns in STEPS[1:12]])]
    out["cancel_n"], out["cancel_ns"] = cN, cns
    out["cancel_total_err"] = tot(cns)
    out["cancel_space_err"] = space_error(:smooth, cN)

    # ---- verification: manufactured solution, exact quadratic, stability limit ------------------------
    p, ex = mms_problem(KAPPA)
    Ts = 0.5
    # Space order: CN with fine time steps on N = 15 ... 127 (dx = 1/16 ... 1/128).
    sNs = [15, 31, 63, 127]
    serr = map(sNs) do N
        x, u, _ = solve_heat(p, N, 4096, Ts; method = :cn)
        maximum(abs, u .- ex.(x, Ts))
    end
    out["mms_space_order"] = fit_order(1 ./ (sNs .+ 1), serr)
    out["mms_dx_min"], out["mms_dx_max"] = 1 / 128, 1 / 16
    # Time orders on N = 255 against a fine CN run on the same grid, 10 ... 80 steps.
    tsteps = [10, 20, 40, 80]
    ref = solve_heat(p, 255, NFINE, Ts; method = :cn)[2]
    terr(m) = [maximum(abs, solve_heat(p, 255, n, Ts; method = m)[2] .- ref) for n in tsteps]
    out["mms_time_order_cn"] = fit_order(Ts ./ tsteps, terr(:cn))
    out["mms_time_order_be"] = fit_order(Ts ./ tsteps, terr(:be))
    out["mms_dt_min"], out["mms_dt_max"] = Ts / 80, Ts / 10
    # A steady quadratic u = x^2 with source -2 kappa: the second difference
    # is exact on it, so every method keeps it to rounding.
    q = HeatProblem(KAPPA, x -> x^2, (x, t) -> -2 * KAPPA, t -> 0.0, t -> 1.0)
    xq, uq, _ = solve_heat(q, 31, 50, 0.5; method = :cn)
    out["quad_err"] = maximum(abs, uq .- xq .^ 2)
    # FTCS's stability limit on N = 31, against von Neumann's 1 / (2 sin^2(N pi dx / 2)).
    out["cfl_measured"] = stability_limit(31)
    out["cfl_theory"] = 1 / (2 * sinpi(31 / 64)^2)

    # ---- validation: physical plausibility on the rough profile -------------------------------------
    # Heat spreading from a symmetric top hat keeps one peak, at the middle.
    # CN with one long step does not: its factor for the fastest modes is
    # close to -1, so the jumps' sharp part survives with its sign flipped
    # and the profile gets extra peaks (measured: max 0.971 against 0.942 at
    # the middle). BE damps those modes and keeps one peak.
    _, ucn, _ = solve_heat(tophat(), 511, 1, TFINAL; method = :cn)
    _, ube, _ = solve_heat(tophat(), 511, 1, TFINAL; method = :be)
    out["cn_peaks"] = local_maxima(ucn)
    out["be_peaks"] = local_maxima(ube)
    out["cn_peak_excess"] = maximum(ucn) - ucn[256]

    # ---- uncertainty: the rough initial profile -------------------------------------------------------
    rNf, rnsf, rcf, _, _ = cheapest(:tophat, :ftcs)
    _, rnsb, rcb, _, _ = cheapest(:tophat, :be)
    rNc, rnsc, rcc, _, _ = cheapest(:tophat, :cn)
    out["robust_n_space"] = rNc
    out["robust_ns_cn"], out["robust_cost_cn"] = rnsc, rcc
    out["robust_cost_ftcs"], out["robust_cost_be"] = rcf, rcb
    rcosts = Dict("ftcs" => rcf, "be" => rcb, "cn" => rcc)
    out["robust_choice"] = first(sort!(collect(keys(rcosts)); by = k -> (rcosts[k], k)))
    out["robust_cost_ratio"] = rcf / rcc
    out["robust_holds"] = out["robust_choice"] == out["choice"] ? "holds" : "fails"

    # ---- where the conclusion was tested --------------------------------------------------------------
    out["valid_n_max"] = max(Nc, rNc)
    out["valid_target"] = TARGET
    return out
end
