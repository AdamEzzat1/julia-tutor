# Thin helpers over JuliaSyntax.SyntaxNode trees, plus a small hand-written
# scope resolver. Everything here is purely syntactic: no code is run or lowered.
#
# Tree shapes this relies on (JuliaSyntax 1.0.x, verified by test/syntax_tests.jl):
# * infix calls keep source order and carry INFIX_FLAG: `a == b` -> call(a, ==, b)
# * `a .= b` is `=` with DOTOP_FLAG; `a[i] -= 1` is `op=`(ref, -, 1)
# * short-form `f(x) = ...` is a `function` node with SHORT_FORM_FUNCTION_FLAG
# * a signature may be wrapped: where(::(call ...), braces), ::(call, RetType)

module Syntax

using JuliaSyntax
const JS = JuliaSyntax
using JuliaSyntax: SyntaxNode, @K_str, kind

export SyntaxNode, kind, @K_str, kids, nodeline, nodecol, ident, is_infix, is_dotop,
       is_short_function, call_parts, function_nodes, signature_call, function_name,
       param_names, local_names, global_decls, walk, ancestors, toplevel_globals,
       defined_type_names, macro_name, is_long_function

kids(n::SyntaxNode) = JS.is_leaf(n) ? SyntaxNode[] : JS.children(n)
nodeline(n::SyntaxNode) = JS.source_location(n)[1]
nodecol(n::SyntaxNode) = JS.source_location(n)[2]
ident(n::SyntaxNode) = kind(n) == K"Identifier" ? (n.val::Symbol) : nothing
is_infix(n::SyntaxNode) = JS.has_flags(n, JS.INFIX_FLAG)
is_dotop(n::SyntaxNode) = JS.has_flags(n, JS.DOTOP_FLAG)
is_short_function(n::SyntaxNode) = kind(n) == K"function" && JS.has_flags(n, JS.SHORT_FORM_FUNCTION_FLAG)
is_long_function(n::SyntaxNode) = kind(n) == K"function" && !is_short_function(n)

"""Pre-order walk; `f(node)` returning `false` stops descent into that node."""
function walk(f, n::SyntaxNode)
    f(n) === false && return nothing
    for c in kids(n)
        walk(f, c)
    end
    return nothing
end

function ancestors(n::SyntaxNode)
    out = SyntaxNode[]
    p = n.parent
    while p !== nothing
        push!(out, p)
        p = p.parent
    end
    return out
end

"""For a `call` node: (callee, positional args). Handles infix and prefix calls."""
function call_parts(n::SyntaxNode)
    cs = kids(n)
    isempty(cs) && return (nothing, SyntaxNode[])
    if is_infix(n) && length(cs) >= 3
        return (cs[2], SyntaxNode[cs[1]; cs[3:end]])
    end
    return (cs[1], SyntaxNode[c for c in cs[2:end] if kind(c) != K"parameters"])
end

"""Name of a callee node: `f`, `Base.push!` -> `push!`; `nothing` if not a plain name."""
function callee_name(c::SyntaxNode)
    k = kind(c)
    k == K"Identifier" && return c.val::Symbol
    if k == K"." && length(kids(c)) == 2
        return callee_name(kids(c)[2])
    end
    return nothing
end

function macro_name(n::SyntaxNode)
    kind(n) == K"macrocall" || return nothing
    m = kids(n)[1]
    kind(m) == K"MacroName" && return m.val::Symbol
    kind(m) == K"." && return macro_name_inner(m)
    return nothing
end
macro_name_inner(m::SyntaxNode) = (k = kids(m); isempty(k) ? nothing : (kind(k[end]) == K"MacroName" ? k[end].val::Symbol : nothing))

function function_nodes(tree::SyntaxNode)
    out = SyntaxNode[]
    walk(n -> (kind(n) == K"function" && push!(out, n); true), tree)
    return out
end

"""The `call` node of a function signature, unwrapping `where` and return-type `::`."""
function signature_call(fn::SyntaxNode)
    sig = kids(fn)[1]
    while kind(sig) in (K"where", K"::") && !isempty(kids(sig))
        sig = kids(sig)[1]
    end
    return kind(sig) == K"call" ? sig : nothing
end

function function_name(fn::SyntaxNode)
    sig = signature_call(fn)
    sig === nothing && return nothing
    callee, _ = call_parts(sig)
    callee === nothing && return nothing
    return callee_name(callee)
end

"""Names bound by a parameter / assignment target (identifiers, `x::T`, `x=default`, tuples, splats)."""
function bound_names!(out::Vector{Symbol}, n::SyntaxNode)
    k = kind(n)
    if k == K"Identifier"
        push!(out, n.val::Symbol)
    elseif k == K"::"
        cs = kids(n)
        length(cs) == 2 && bound_names!(out, cs[1])     # `::T` alone binds nothing
    elseif k == K"="
        bound_names!(out, kids(n)[1])
    elseif k in (K"tuple", K"parameters", K"...")
        foreach(c -> bound_names!(out, c), kids(n))
    end
    return out
end

"""Positional parameter names of a function, in order (keyword arguments excluded)."""
function param_names(fn::SyntaxNode; keywords::Bool = false)
    sig = signature_call(fn)
    sig === nothing && return Symbol[]
    out = Symbol[]
    for c in kids(sig)[2:end]
        if kind(c) == K"parameters"
            keywords && bound_names!(out, c)
        else
            bound_names!(out, c)
        end
    end
    return out
end

function body_of(fn::SyntaxNode)
    cs = kids(fn)
    return length(cs) >= 2 ? cs[2] : nothing
end

"""
    local_names(fn) -> Set{Symbol}

Over-approximation of the names that are local inside function `fn`: parameters
(including keywords), assignment targets, loop/comprehension variables, `local`
declarations and `catch` variables, *including those of nested closures*
(merging nested scopes can only hide a finding, never invent one).
Names declared `global` are removed.
"""
function local_names(fn::SyntaxNode)
    out = Symbol[]
    append!(out, param_names(fn; keywords = true))
    body = body_of(fn)
    body === nothing && return Set(out)
    walk(body) do n
        k = kind(n)
        if k == K"=" && !is_dotop(n)
            lhs = kids(n)[1]
            if kind(lhs) == K"call"            # nested short-form function
                foreach(c -> bound_names!(out, c), kids(lhs)[2:end])
            else
                bound_names!(out, lhs)
            end
        elseif k == K"op=" && !is_dotop(n)
            bound_names!(out, kids(n)[1])
        elseif k == K"in" && n.parent !== nothing && kind(n.parent) == K"iteration"
            bound_names!(out, kids(n)[1])
        elseif k == K"local"
            foreach(c -> bound_names!(out, c), kids(n))
        elseif k == K"catch" && !isempty(kids(n))
            bound_names!(out, kids(n)[1])
        elseif k == K"function" || k == K"->"
            if k == K"function"
                append!(out, param_names(n; keywords = true))
            else
                bound_names!(out, kids(n)[1])
            end
        end
        return true
    end
    return setdiff(Set(out), global_decls(fn))
end

function global_decls(fn::SyntaxNode)
    out = Symbol[]
    walk(fn) do n
        kind(n) == K"global" && foreach(c -> bound_names!(out, c), kids(n))
        true
    end
    return Set(out)
end

"""Statements at file top level and inside `module` blocks."""
function toplevel_statements(tree::SyntaxNode)
    out = SyntaxNode[]
    for s in kids(tree)
        if kind(s) == K"module" && length(kids(s)) >= 2
            append!(out, toplevel_statements(kids(s)[2]))
        else
            push!(out, s)
        end
    end
    return out
end

"""(non-const global names => first assignment node, const global names)."""
function toplevel_globals(tree::SyntaxNode)
    nonconst = Dict{Symbol,SyntaxNode}()
    consts = Set{Symbol}()
    for s in toplevel_statements(tree)
        k = kind(s)
        if k == K"const"
            names = Symbol[]
            foreach(c -> kind(c) == K"=" && bound_names!(names, kids(c)[1]), kids(s))
            union!(consts, names)
        elseif k == K"global" && length(kids(s)) == 1 && kind(kids(s)[1]) == K"="
            names = bound_names!(Symbol[], kids(kids(s)[1])[1])
            foreach(nm -> get!(nonconst, nm, s), names)
        elseif k == K"=" && !is_dotop(s) && kind(kids(s)[1]) != K"call"
            names = bound_names!(Symbol[], kids(s)[1])
            foreach(nm -> get!(nonconst, nm, s), names)
        end
    end
    for c in consts
        delete!(nonconst, c)
    end
    return nonconst, consts
end

"""Names of types defined in the file (struct, abstract, primitive)."""
function defined_type_names(tree::SyntaxNode)
    out = Set{Symbol}()
    walk(tree) do n
        if kind(n) in (K"struct", K"abstract", K"primitive") && !isempty(kids(n))
            h = kids(n)[1]
            while kind(h) in (K"<:", K"curly") && !isempty(kids(h))
                h = kids(h)[1]
            end
            nm = ident(h)
            nm === nothing || push!(out, nm)
        end
        true
    end
    return out
end

end # module Syntax
