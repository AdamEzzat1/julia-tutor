# Lessons: short concept texts with predict-the-output checks.
#
# * Every answer key is verified by running the snippet in a fresh process of the
#   pinned Julia and comparing its stdout with the keyed option (`tutor lessons
#   verify`); no other option may also match. `verified_on` must equal the pinned
#   release, so a Julia upgrade forces re-verification (invariant 4).
# * Every wrong option maps to a named misconception with its own feedback.
# * A wrong first answer gets that feedback plus the check's hint, and a second
#   try; the answer is revealed only after the second miss.

module Lessons

using TOML, Dates
using ..Models, ..Runner

export Lesson, Check, load_lessons, verify_lessons, run_lesson, validate_lessons

const LESSON_DIR = normpath(joinpath(@__DIR__, "..", "lessons"))

struct Check
    id::String
    prompt::String
    code::String
    options::Vector{String}
    answer::Int                          # 1-based index into options
    hint::String                         # given after a wrong first try; never the answer
    explanation::String                  # shown after the check is settled
    misconceptions::Dict{Int,Tuple{String,String}}   # option => (misconception id, feedback)
end

struct Lesson
    id::String
    title::String
    kcs::Vector{String}
    prerequisites::Vector{String}
    verified_on::String
    body::String
    checks::Vector{Check}
end

function load_lesson(path::String)
    d = TOML.parsefile(path)
    checks = Check[]
    for c in d["check"]
        mis = Dict{Int,Tuple{String,String}}()
        for m in get(c, "misconception", Any[])
            mis[m["option"]] = (m["id"], m["feedback"])
        end
        push!(checks, Check(c["id"], c["prompt"], c["code"], String.(c["options"]), c["answer"],
                            c["hint"], c["explanation"], mis))
    end
    return Lesson(d["id"], d["title"], String.(d["kcs"]), String.(d["prerequisites"]),
                  d["verified_on"], d["body"], checks)
end

load_lessons(dir::String = LESSON_DIR) =
    [load_lesson(joinpath(dir, f)) for f in sort!(readdir(dir)) if endswith(f, ".toml")]

"""Structural checks that need no Julia run. Returns a list of problems."""
function validate_lessons(lessons::Vector{Lesson})
    problems = String[]
    ids = Set(l.id for l in lessons)
    for l in lessons
        l.verified_on == string(VERSION) ||
            push!(problems, "$(l.id): verified_on = $(l.verified_on) but running $(VERSION); re-verify")
        for p in l.prerequisites
            p in ids || push!(problems, "$(l.id): unknown prerequisite $p")
        end
        for c in l.checks
            where_ = "$(l.id)/$(c.id)"
            n = length(c.options)
            n >= 3 || push!(problems, "$where_: needs at least 3 options")
            1 <= c.answer <= n || push!(problems, "$where_: answer index out of range")
            allunique(c.options) || push!(problems, "$where_: duplicate options")
            for i in 1:n
                i == c.answer && continue
                haskey(c.misconceptions, i) || push!(problems, "$where_: wrong option $i has no misconception")
            end
            haskey(c.misconceptions, c.answer) && push!(problems, "$where_: the answer is mapped to a misconception")
            occursin(c.options[c.answer], c.hint) && push!(problems, "$where_: hint contains the answer")
        end
    end
    # prerequisite graph must be acyclic (depth-first search, deterministic order)
    byid = Dict(l.id => l for l in lessons)
    state = Dict{String,Int}()
    function visit(id, stack)
        get(state, id, 0) == 2 && return
        if get(state, id, 0) == 1
            push!(problems, "prerequisite cycle: $(join([stack; id], " -> "))")
            return
        end
        state[id] = 1
        haskey(byid, id) && foreach(p -> visit(p, [stack; id]), byid[id].prerequisites)
        state[id] = 2
    end
    foreach(l -> visit(l.id, String[]), lessons)
    return problems
end

"""Run every snippet on this (pinned) Julia; returns a list of problems."""
function verify_lessons(lessons::Vector{Lesson}; log = stdout)
    problems = validate_lessons(lessons)
    project = normpath(joinpath(@__DIR__, ".."))
    for l in lessons, c in l.checks
        file = tempname() * ".jl"
        write(file, c.code)
        code, timed_out, out = Runner.run_julia_script(file, String[]; project, timeout = 120)
        rm(file; force = true)
        got = rstrip(replace(out, "\r\n" => "\n"))
        where_ = "$(l.id)/$(c.id)"
        if timed_out
            push!(problems, "$where_: timed out")
        elseif code != 0
            push!(problems, "$where_: snippet exited with code $code:\n$got")
        elseif got != c.options[c.answer]
            push!(problems, "$where_: keyed answer is $(repr(c.options[c.answer])) but the snippet printed $(repr(got))")
        else
            others = [i for (i, o) in enumerate(c.options) if i != c.answer && o == got]
            isempty(others) || push!(problems, "$where_: output also matches option(s) $others")
            println(log, "  ok $where_: ", repr(got))
        end
    end
    return problems
end

# -----------------------------------------------------------------------------
# Interactive runner
# -----------------------------------------------------------------------------

const LETTERS = "abcdefgh"

function load_state(path::String)
    isfile(path) ? TOML.parsefile(path) : Dict{String,Any}("kc" => Dict{String,Any}(), "items" => Dict{String,Any}())
end

function save_state(path::String, state)
    mkpath(dirname(abspath(path)))
    open(path, "w") do io
        TOML.print(io, state; sorted = true)
    end
end

"""
    run_lesson(lesson; input, output, state_path, today)

`input` supplies answers (one letter per line), so the same function drives the
terminal and the tests. Returns (first_try_correct::Vector{Bool}, state).
"""
function run_lesson(l::Lesson; input::IO = stdin, output::IO = stdout,
                    state_path::String = joinpath(".tutor", "state.toml"), today::Date = Dates.today(),
                    all_lessons::Vector{Lesson} = Lesson[])
    state = load_state(state_path)
    println(output, "# ", l.title, "\n")
    for p in l.prerequisites
        done = haskey(state["items"], "$p/") || any(k -> startswith(k, "$p/"), keys(state["items"]))
        done || println(output, "(Prerequisite not done yet: $p. You may continue, but it builds on it.)\n")
    end
    println(output, strip(l.body), "\n")
    results = Bool[]
    for c in l.checks
        println(output, "## Predict the output\n\n", strip(c.prompt), "\n\n```julia\n", rstrip(c.code), "\n```\n")
        for (i, o) in enumerate(c.options)
            println(output, "  ", LETTERS[i], ") ", replace(o, "\n" => "\n     "))
        end
        first_try = ask(input, output, length(c.options))
        quality = 5
        if first_try == c.answer
            println(output, "Correct.")
        else
            mid, fb = c.misconceptions[first_try]
            println(output, "Not quite. ", fb)
            println(output, "Hint: ", c.hint)
            second = ask(input, output, length(c.options))
            if second == c.answer
                println(output, "Correct on the second try.")
                quality = 3
            else
                second in keys(c.misconceptions) && println(output, c.misconceptions[second][2])
                println(output, "The answer is ", LETTERS[c.answer], ").")
                quality = 1
            end
            hist = get!(state, "misconceptions", Dict{String,Any}())
            hist[mid] = get(hist, mid, 0) + 1
        end
        println(output, strip(c.explanation), "\n")
        correct = first_try == c.answer
        push!(results, correct)
        guess = 1 / length(c.options)
        for kc in l.kcs
            prior = Float64(get(state["kc"], kc, BKTParams().p_init))
            state["kc"][kc] = Models.bkt_update(prior, correct, BKTParams(p_guess = guess))
        end
        key = "$(l.id)/$(c.id)"
        item = get(state["items"], key, Dict("repetitions" => 0, "interval_days" => 0, "easiness" => 2.5))
        s = Models.sm2_update(SM2State(item["repetitions"], item["interval_days"], item["easiness"]), quality)
        state["items"][key] = Dict("repetitions" => s.repetitions, "interval_days" => s.interval_days,
                                   "easiness" => s.easiness, "due" => string(Models.sm2_due(s, today)))
    end
    for kc in l.kcs
        println(output, "P(knows $kc) = ", round(state["kc"][kc]; digits = 2))
    end
    save_state(state_path, state)
    return results, state
end

function ask(input::IO, output::IO, n::Int)
    while true
        print(output, "Your answer (", LETTERS[1], "-", LETTERS[n], "): ")
        eof(input) && error("no more input")
        s = lowercase(strip(readline(input)))
        if length(s) == 1 && (i = findfirst(==(s[1]), LETTERS)) !== nothing && i <= n
            println(output)
            return i
        end
        println(output, "Please type one letter.")
    end
end

end # module Lessons
