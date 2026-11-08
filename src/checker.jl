# Static misconception checker over JuliaSyntax trees.
#
# Contract (see CLAUDE.md, invariants 1-3 and 8):
# * Deterministic: same input bytes -> byte-identical output. Findings are sorted;
#   no Dict/Set iteration order reaches the output.
# * A rule states only what the syntax tree (plus the scope resolver in syntax.jl)
#   can establish. Type and performance facts come from measurement (explain.jl);
#   a rule may only point to the likely location.
# * Severity ADVICE never affects the exit code.

module Checker

using JuliaSyntax
const JS = JuliaSyntax
using ..Syntax

export Severity, ADVICE, WARN, ERROR, Finding, RuleMeta, Rule, RULES, meta, check,
       check_source, check_paths, format_findings, exit_code, rule_by_id

@enum Severity ADVICE = 0 WARN = 1 ERROR = 2

struct Finding
    rule::String
    severity::Severity
    file::String
    line::Int
    col::Int
    message::String
end

# Total order used for output: location first, then rule, then message.
sortkey(f::Finding) = (f.file, f.line, f.col, f.rule, f.message)

"""
Metadata every rule must provide. `answer_tokens` are code fragments that would
give the fix away; the level-1 hint must contain none of them (tested).
"""
struct RuleMeta
    id::String
    name::String
    kc::String                    # knowledge component
    severity::Severity            # default severity (a rule may downgrade per finding)
    fp_risk::String               # honest false-positive analysis
    measured_by::String           # which measurement confirms or refutes the suspicion
    hints::NTuple{3,String}       # level 1 never gives the answer
    answer_tokens::Vector{String}
end

abstract type Rule end

"""Per-file analysis context, computed once and shared by all rules."""
struct FileContext
    file::String
    src::String
    tree::SyntaxNode
    nonconst_globals::Dict{Symbol,SyntaxNode}
    type_names::Set{Symbol}
end

finding(r::Rule, ctx::FileContext, n::SyntaxNode, msg::String; severity::Severity = meta(r).severity) =
    Finding(meta(r).id, severity, ctx.file, nodeline(n), nodecol(n), msg)

include("rules/vector_any.jl")
include("rules/abstract_field.jl")
include("rules/bang_convention.jl")
include("rules/eachindex.jl")
include("rules/float_equality.jl")
include("rules/nonconst_global.jl")

const RULES = (VectorAnyLiteral(), AbstractFieldType(), MutatesWithoutBang(),
               BangWithoutMutation(), OneToLength(), FloatLiteralEquality(),
               NonConstGlobal())

rule_by_id(id::AbstractString) = only(r for r in RULES if meta(r).id == id)

"""
    check_source(src, file; rules = RULES) -> Vector{Finding}

Parse `src` and run every rule. A parse error yields one ERROR finding (JT000).
"""
function check_source(src::AbstractString, file::AbstractString; rules = RULES)
    src = String(src)
    tree = try
        JS.parseall(SyntaxNode, src; filename = file)
    catch err
        err isa JS.ParseError || rethrow()
        d = err.diagnostics[1]
        line, col = JS.source_location(err.source, JS.first_byte(d))
        return [Finding("JT000", ERROR, String(file), line, col, "parse error: " * d.message)]
    end
    nonconst, _ = toplevel_globals(tree)
    ctx = FileContext(String(file), src, tree, nonconst, defined_type_names(tree))
    out = Finding[]
    for r in rules
        append!(out, check(r, ctx))
    end
    return sort!(unique!(out); by = sortkey)
end

"""All `.jl` files under `paths` (files or directories), sorted, as given-relative paths."""
function collect_files(paths)
    files = String[]
    for p in paths
        if isdir(p)
            for (root, _, fs) in walkdir(p), f in fs
                endswith(f, ".jl") && push!(files, joinpath(root, f))
            end
        else
            push!(files, p)
        end
    end
    return sort!(unique!(map(f -> replace(f, '\\' => '/'), files)))
end

function check_paths(paths; rules = RULES, relative_to::Union{Nothing,String} = nothing)
    out = Finding[]
    for f in collect_files(paths)
        shown = relative_to === nothing ? f : replace(relpath(f, relative_to), '\\' => '/')
        append!(out, check_source(read(f, String), shown; rules))
    end
    return sort!(out; by = sortkey)
end

"""Text rendering. `hints` = number of hint levels to show (0-3)."""
function format_findings(findings::Vector{Finding}; hints::Int = 0)
    io = IOBuffer()
    for f in sort(findings; by = sortkey)
        println(io, f.file, ":", f.line, ":", f.col, ": ", f.severity, " ", f.rule, " ", f.message)
        if hints > 0 && f.rule != "JT000"
            m = meta(rule_by_id(f.rule))
            for lvl in 1:min(hints, 3)
                println(io, "    hint ", lvl, ": ", m.hints[lvl])
            end
        end
    end
    return String(take!(io))
end

"""1 if any finding is WARN or ERROR; ADVICE never changes the exit code."""
exit_code(findings::Vector{Finding}) = any(f -> f.severity >= WARN, findings) ? 1 : 0

end # module Checker
