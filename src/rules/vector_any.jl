# JT001: `[]` and `Dict()` create containers with element type Any.

struct VectorAnyLiteral <: Rule end

meta(::VectorAnyLiteral) = RuleMeta(
    "JT001", "vector-any-literal", "container-element-types", WARN,
    "Low for the fact (`[]` is always a `Vector{Any}`, `Dict()` a `Dict{Any,Any}`: " *
    "that is syntax, not inference). Medium for the advice: a heterogeneous " *
    "container is sometimes intended. Comparisons such as `x == []` are skipped.",
    "explain: inferred return types of the enclosing function (Base.return_types)",
    ("What element type does this container get when it is created empty? " *
     "Try `typeof(...)` on it in the REPL.",
     "An empty literal has no elements to infer an element type from, so Julia " *
     "uses `Any`. Everything you push into it is then stored boxed, and code " *
     "reading from it cannot know the element type.",
     "Name the element type: `Term[]`, `Float64[]`, `Vector{Int}()` or " *
     "`Dict{Symbol,Int}()`."),
    ["Term[]", "Float64[]", "Vector{", "Dict{"])

const COMPARISON_OPS = (:(==), :(!=), :(===), :(!==), :≠, :isequal)

function is_comparison_operand(n::SyntaxNode)
    p = n.parent
    (p === nothing || kind(p) != K"call") && return false
    callee, _ = call_parts(p)
    return callee !== nothing && ident(callee) in COMPARISON_OPS
end

function check(r::VectorAnyLiteral, ctx::FileContext)
    out = Finding[]
    walk(ctx.tree) do n
        if kind(n) == K"vect" && isempty(kids(n)) && !is_comparison_operand(n)
            push!(out, finding(r, ctx, n, "`[]` creates a Vector{Any}"))
        elseif kind(n) == K"call" && !is_infix(n) && length(kids(n)) == 1 &&
               ident(kids(n)[1]) === :Dict && !is_comparison_operand(n)
            push!(out, finding(r, ctx, n, "`Dict()` creates a Dict{Any,Any}"))
        end
        true
    end
    return out
end
