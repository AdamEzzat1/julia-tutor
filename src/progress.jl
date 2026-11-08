# The learner model over time: BKT per knowledge component, updated from
# lesson answers (lessons.jl) and from attempts at holes (this file), plus the
# `tutor progress` report. State lives in one TOML file (default
# `.tutor/state.toml`, gitignored).
#
# What counts as one observation of a hole (the learning scientist's objection
# to "every `tutor explain` run is evidence" is that re-running unchanged code
# would inflate mastery):
# * the hole is implemented (not its TODO body) and the files parse and load;
# * its source differs (ignoring whitespace) from the last recorded attempt;
# * the evidence is unambiguous. A dependent testset whose only problems are
#   TODO errors of *other* holes is already explained ("excused") and is no
#   evidence either way. Then: "correct" when every other dependent testset
#   passes; "incorrect" when a failing one depends on this hole and on no other
#   hole of the stage. A failure shared with another hole says nothing about
#   which one is wrong, so it is not recorded.

module Progress

using TOML, Dates, SHA
using ..Models

export Observation, attempt_hash, observe, apply_observations!, format_progress,
       load_state, save_state, CODE_BKT

struct Observation
    project::String
    hole::String
    kc::String
    correct::Bool
    hash::String
end

"""Whitespace-insensitive hash of a hole's source: reformatting is not a new attempt."""
attempt_hash(src::AbstractString) = bytes2hex(sha1(filter(!isspace, String(src))))

"""
BKT parameters for code attempts (priors, not fitted; fitting is M6). Guessing
an implementation that passes every dependent testset is unlikely (p_guess
0.05); a student who knows the idea still writes bugs (p_slip 0.15).
"""
const CODE_BKT = BKTParams(p_init = 0.2, p_learn = 0.15, p_guess = 0.05, p_slip = 0.15)

"""
    observe(hole, deps, failing, stage_holes; excused) -> :correct | :incorrect | :ambiguous | :no_evidence

`deps[h]` are the testsets that depend on hole `h` (measured map plus TODO
evidence); `failing` the names of failing testsets; `stage_holes` the hole ids
of the current stage; `excused` the failing testsets whose only problems are
TODO errors (of holes other than `hole`, since `hole` is implemented).
"""
function observe(hole::String, deps::Dict{String,Vector{String}}, failing::Set{String},
                 stage_holes::Vector{String}; excused::Set{String} = Set{String}())
    mine = filter(!in(excused), get(deps, hole, String[]))
    isempty(mine) && return :no_evidence
    bad = filter(in(failing), mine)
    isempty(bad) && return :correct
    others = filter(!=(hole), stage_holes)
    for t in bad
        any(o -> t in get(deps, o, String[]), others) || return :incorrect
    end
    return :ambiguous
end

function load_state(path::String)
    isfile(path) || return Dict{String,Any}("kc" => Dict{String,Any}(), "items" => Dict{String,Any}())
    return TOML.parsefile(path)
end

function save_state(path::String, state)
    mkpath(dirname(abspath(path)))
    open(path, "w") do io
        TOML.print(io, state; sorted = true)
    end
end

"""
    apply_observations!(state, obs; θ = CODE_BKT) -> Vector{String}

Update BKT and per-hole attempt counts; returns one human-readable line per
observation. An observation whose hash equals the hole's last recorded attempt
is not counted again.
"""
function apply_observations!(state::Dict{String,Any}, obs::Vector{Observation}; θ::BKTParams = CODE_BKT)
    holes = get!(state, "holes", Dict{String,Any}())
    kcs = get!(state, "kc", Dict{String,Any}())
    lines = String[]
    for o in obs
        key = "$(o.project)/$(o.hole)"
        h = get!(holes, key, Dict{String,Any}("attempts" => 0, "correct" => 0, "last_hash" => "",
                                              "last_correct" => false))
        if h["last_hash"] == o.hash
            push!(lines, "$(o.hole): unchanged since the last recorded attempt (not counted again)")
            continue
        end
        prior = Float64(get(kcs, o.kc, θ.p_init))
        post = Models.bkt_update(prior, o.correct, θ)
        kcs[o.kc] = post
        h["attempts"] += 1
        h["correct"] += o.correct
        h["last_hash"] = o.hash
        h["last_correct"] = o.correct
        push!(lines, "$(o.hole): attempt $(h["attempts"]), $(o.correct ? "correct" : "incorrect"); " *
                     "P(knows $(o.kc)) $(round(prior; digits = 2)) -> $(round(post; digits = 2))")
    end
    return lines
end

"""
    format_progress(state; today) -> String

The `tutor progress` report. Deterministic given `state` and `today`.
"""
function format_progress(state::Dict{String,Any}; today::Date)
    io = IOBuffer()
    kcs = get(state, "kc", Dict{String,Any}())
    println(io, "Knowledge components (BKT with prior parameters, not fitted):")
    isempty(kcs) && println(io, "  none yet: take a lesson (`tutor lesson L01`) or run `tutor explain`")
    for k in sort!(collect(keys(kcs)))
        p = Float64(kcs[k])
        println(io, "  ", rpad(k, 30), rpad(string(round(p; digits = 2)), 6),
                p >= 0.95 ? "mastered (P >= 0.95)" : "")
    end
    holes = get(state, "holes", Dict{String,Any}())
    println(io, "\nHole attempts (one per distinct version of the code):")
    isempty(holes) && println(io, "  none recorded")
    for k in sort!(collect(keys(holes)))
        h = holes[k]
        println(io, "  ", rpad(k, 30), "attempts $(h["attempts"]), correct $(h["correct"]), last ",
                h["last_correct"] ? "correct" : "incorrect")
    end
    items = get(state, "items", Dict{String,Any}())
    due = sort!([k for k in keys(items) if haskey(items[k], "due") && Date(items[k]["due"]) <= today])
    println(io, "\nLesson checks due for review on $today (SM-2):")
    isempty(due) && println(io, "  none", isempty(items) ? "" :
        "; next: " * minimum(String(items[k]["due"]) for k in keys(items) if haskey(items[k], "due")))
    foreach(k -> println(io, "  ", k, " (due ", items[k]["due"], ")"), due)
    mis = get(state, "misconceptions", Dict{String,Any}())
    if !isempty(mis)
        println(io, "\nMisconceptions chosen in lessons:")
        for k in sort!(collect(keys(mis)))
            println(io, "  ", rpad(k, 30), "x", mis[k])
        end
    end
    return String(take!(io))
end

end # module Progress
