# JT003 / JT004: the `!` naming convention for functions that mutate arguments.

struct MutatesWithoutBang <: Rule end
struct BangWithoutMutation <: Rule end

meta(::MutatesWithoutBang) = RuleMeta(
    "JT003", "mutates-without-bang", "mutation-convention", WARN,
    "Detects writes into a positional parameter (`p[i] = `, `p.f = `, `p .= `, " *
    "`p[i] += `) and passing it as the first argument of a `!` function. Skipped " *
    "when the parameter is rebound anywhere in the body (`p = copy(p)`). Misses " *
    "mutation through aliases (`q = p; q[1] = 0`) and through non-`!` callees.",
    "test: callers' inputs compared before/after the call (behavioural)",
    ("After calling this function, is the caller's argument still the value it " *
     "passed in?",
     "This function changes one of its arguments in place. Julia's convention is " *
     "that such functions end in `!`, so callers know their data may change; " *
     "without it, a caller reusing the argument gets a silent aliasing bug.",
     "Either rename it with a trailing `!` (and update callers), or work on a " *
     "`copy` of the argument so the caller's value is untouched."),
    ["!(", "copy("])

meta(::BangWithoutMutation) = RuleMeta(
    "JT004", "bang-without-mutation", "mutation-convention", ADVICE,
    "Only fires when no method of the same name in the file writes into anything, " *
    "calls any `!` function, or uses `.=`; mutation hidden in a non-`!` helper is " *
    "missed, which would be a false positive.",
    "none (naming convention)",
    ("What does the trailing `!` in a Julia function name promise its callers?",
     "By convention `!` marks functions that modify (at least) one argument. This " *
     "function, in every method in this file, leaves its arguments unchanged.",
     "Remove the `!` from the name, or, if it is meant to update an argument in " *
     "place, make it do that."),
    ["Remove the", "rename"])

"""Root identifier of an assignment target: `p` for `p`, `p[i]`, `p.f`, `p[i].f[j]`."""
function target_root(n::SyntaxNode)
    while kind(n) in (K"ref", K".") && !isempty(kids(n))
        n = kids(n)[1]
    end
    return ident(n)
end

"""
    mutated_params(fn) -> (hits, any_mutation)

`hits`: positional parameters of `fn` written into (param => first node).
`any_mutation`: whether the body writes into anything or calls any `!` function.
"""
function mutated_params(fn::SyntaxNode)
    params = Set(param_names(fn))
    rebound = Set{Symbol}()
    hits = Pair{Symbol,SyntaxNode}[]
    any_mutation = false
    length(kids(fn)) >= 2 || return hits, any_mutation
    walk(kids(fn)[2]) do n
        k = kind(n)
        if k in (K"=", K"op=")
            lhs = kids(n)[1]
            if kind(lhs) in (K"ref", K".") || is_dotop(n)
                any_mutation = true
                root = target_root(lhs)
                root !== nothing && root in params && push!(hits, root => n)
            elseif k == K"=" && ident(lhs) !== nothing
                push!(rebound, ident(lhs))
            end
        elseif k == K"call"
            callee, args = call_parts(n)
            nm = callee === nothing ? nothing : Syntax.callee_name(callee)
            if nm !== nothing && endswith(String(nm), "!")
                any_mutation = true
                if !isempty(args)
                    root = target_root(args[1])
                    root !== nothing && root in params && push!(hits, root => n)
                end
            end
        end
        true
    end
    return filter(h -> !(h.first in rebound), hits), any_mutation
end

function check(r::MutatesWithoutBang, ctx::FileContext)
    out = Finding[]
    for fn in function_nodes(ctx.tree)
        name = function_name(fn)
        (name === nothing || endswith(String(name), "!")) && continue
        hits, _ = mutated_params(fn)
        isempty(hits) && continue
        p, node = first(hits)
        push!(out, finding(r, ctx, node, "`$name` mutates its argument `$p` but its name has no `!`"))
    end
    return out
end

function check(r::BangWithoutMutation, ctx::FileContext)
    out = Finding[]
    by_name = Dict{Symbol,Vector{SyntaxNode}}()
    for fn in function_nodes(ctx.tree)
        name = function_name(fn)
        name === nothing && continue
        push!(get!(by_name, name, SyntaxNode[]), fn)
    end
    for name in sort!(collect(keys(by_name)))          # sorted: no Dict order in output
        endswith(String(name), "!") || continue
        methods = by_name[name]
        any(fn -> mutated_params(fn)[2], methods) && continue
        push!(out, finding(r, ctx, methods[1],
              "`$name` ends in `!` but no method of it in this file mutates anything"))
    end
    return out
end
