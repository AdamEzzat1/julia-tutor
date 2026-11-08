# JT007: a function reads a non-const global variable.

struct NonConstGlobal <: Rule end

meta(::NonConstGlobal) = RuleMeta(
    "JT007", "nonconst-global-read", "global-scope-performance", WARN,
    "Scope comes from syntax.jl's resolver, which over-approximates locals " *
    "(nested scopes are merged), so it can miss a read but should not invent one. " *
    "Globals created via `eval`, another file's `include`, or macros are not " *
    "seen. The finding is a location; whether it costs anything is measured.",
    "explain: inferred return types of the function (measured)",
    ("Inside this function, what does the compiler know about the type of this " *
     "name? Could another part of the program assign it a different type later?",
     "A non-`const` global can be rebound to a value of any type at any time, so " *
     "code that reads it cannot be specialised on its type: every use is a " *
     "dynamic lookup, and the function's return type often becomes `Any`.",
     "Declare it `const` if it never changes, or pass it in as an argument " *
     "(then the function is specialised on its type)."),
    ["const ", "as an argument"])

is_field_name(n::SyntaxNode) = n.parent !== nothing && kind(n.parent) == K"." &&
                               length(kids(n.parent)) == 2 && kids(n.parent)[2] === n

function is_keyword_name(n::SyntaxNode)
    p = n.parent
    (p === nothing || kind(p) != K"=" || kids(p)[1] !== n) && return false
    return p.parent !== nothing && kind(p.parent) == K"parameters"
end

function check(r::NonConstGlobal, ctx::FileContext)
    out = Finding[]
    isempty(ctx.nonconst_globals) && return out
    for fn in function_nodes(ctx.tree)
        # nested functions are covered by their enclosing function's walk
        any(a -> kind(a) == K"function", ancestors(fn)) && continue
        length(kids(fn)) >= 2 || continue
        locals = local_names(fn)
        fname = something(function_name(fn), Symbol("<anonymous>"))
        seen = Set{Symbol}()
        walk(kids(fn)[2]) do n
            kind(n) == K"quote" && return false
            nm = ident(n)
            if nm !== nothing && haskey(ctx.nonconst_globals, nm) && !(nm in locals) &&
               !(nm in seen) && !is_field_name(n) && !is_keyword_name(n)
                push!(seen, nm)
                push!(out, finding(r, ctx, n, "`$fname` reads non-const global `$nm`"))
            end
            true
        end
    end
    return out
end
