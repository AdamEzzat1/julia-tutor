# Interpretable, non-generative learner and fault models. Every function here is
# a pure function of its inputs (no clocks, no randomness); callers pass dates.

module Models

using Dates

export BKTParams, bkt_update, SM2State, sm2_update, sm2_due, ochiai, rank_by_ochiai

# -----------------------------------------------------------------------------
# Bayesian Knowledge Tracing (Corbett & Anderson, 1994)
# -----------------------------------------------------------------------------

"""
    BKTParams(p_init, p_learn, p_guess, p_slip)

Per-knowledge-component parameters. For a k-option multiple-choice check the
guess probability is about 1/k. Defaults are priors, not fitted values; fitting
them per item is milestone M6 (Rasch/IRT calibration).
"""
struct BKTParams
    p_init::Float64
    p_learn::Float64
    p_guess::Float64
    p_slip::Float64
    function BKTParams(p_init, p_learn, p_guess, p_slip)
        for (nm, v) in (("p_init", p_init), ("p_learn", p_learn), ("p_guess", p_guess), ("p_slip", p_slip))
            0 <= v <= 1 || throw(ArgumentError("$nm must be in [0, 1], got $v"))
        end
        p_guess + p_slip < 1 || throw(ArgumentError("p_guess + p_slip must be < 1 (else a correct answer is evidence of not knowing)"))
        return new(p_init, p_learn, p_guess, p_slip)
    end
end
BKTParams(; p_init = 0.2, p_learn = 0.15, p_guess = 0.25, p_slip = 0.1) =
    BKTParams(p_init, p_learn, p_guess, p_slip)

"""
    bkt_update(p_known, correct, params) -> Float64

Posterior P(known) after one observation, followed by the learning transition:
P(L | obs) by Bayes' rule, then P(L') = P(L | obs) + (1 - P(L | obs)) * p_learn.
"""
function bkt_update(p_known::Float64, correct::Bool, θ::BKTParams)
    if correct
        num = p_known * (1 - θ.p_slip)
        den = num + (1 - p_known) * θ.p_guess
    else
        num = p_known * θ.p_slip
        den = num + (1 - p_known) * (1 - θ.p_guess)
    end
    posterior = num / den
    return posterior + (1 - posterior) * θ.p_learn
end

# -----------------------------------------------------------------------------
# SM-2 spaced repetition (Wozniak, 1990)
# -----------------------------------------------------------------------------

struct SM2State
    repetitions::Int
    interval_days::Int
    easiness::Float64
end
SM2State() = SM2State(0, 0, 2.5)

"""
    sm2_update(s, quality) -> SM2State

`quality` in 0:5. In this tutor: 5 = correct first try, 3 = correct after the
hint, 1 = wrong twice (answer revealed).
"""
function sm2_update(s::SM2State, quality::Int)
    0 <= quality <= 5 || throw(ArgumentError("quality must be in 0:5, got $quality"))
    q = quality
    ef = max(1.3, s.easiness + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02)))
    if q < 3
        return SM2State(0, 1, ef)
    end
    reps = s.repetitions + 1
    interval = reps == 1 ? 1 : reps == 2 ? 6 : round(Int, s.interval_days * s.easiness)
    return SM2State(reps, interval, ef)
end

sm2_due(s::SM2State, reviewed::Date) = reviewed + Day(s.interval_days)

# -----------------------------------------------------------------------------
# Spectrum-based fault localisation: Ochiai (Abreu et al., 2006)
# -----------------------------------------------------------------------------

"""
    ochiai(failed_dep, passed_dep, total_failed) -> Float64

`failed_dep`/`passed_dep`: failing/passing tests that depend on the element;
`total_failed`: all failing tests. 0 when undefined.

In this tutor the "spectrum" is the *measured test-to-hole dependency map*
(tests that fail when exactly that hole is opened in the reference), not line
coverage. That is honest for ranking holes and says nothing about lines.
"""
function ochiai(failed_dep::Int, passed_dep::Int, total_failed::Int)
    den = sqrt(total_failed * (failed_dep + passed_dep))
    return den == 0 ? 0.0 : failed_dep / den
end

"""
    rank_by_ochiai(deps, failing, holes) -> Vector{Tuple{String,Float64,Int,Int}}

`deps[h]` = tests depending on hole `h`; `failing` = failing tests. Returns
(hole, score, failed_dep, passed_dep) sorted by score descending, then by the
order of `holes` (stable, deterministic).
"""
function rank_by_ochiai(deps::Dict{String,Vector{String}}, failing::Set{String}, holes::Vector{String})
    F = length(failing)
    rows = Tuple{String,Float64,Int,Int}[]
    for h in holes
        d = get(deps, h, String[])
        ef = count(in(failing), d)
        push!(rows, (h, ochiai(ef, length(d) - ef, F), ef, length(d) - ef))
    end
    order = sortperm(1:length(rows); by = i -> (-rows[i][2], i))
    return rows[order]
end

end # module Models
