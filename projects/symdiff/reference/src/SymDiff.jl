"""
    SymDiff

A small computer-algebra core written from scratch: typed term trees, a
canonicalising simplifier, symbolic differentiation by multiple dispatch,
one-way pattern matching, and a term-rewriting engine whose termination is
argued with a size measure.

It does not depend on Symbolics.jl, SymbolicUtils.jl or Metatheory.jl. The goal
is to understand how such a system works, not to call one.

Lines starting with `# HOLE:` mark functions the scaffolder can open. They are
removed from the generated starter project.
"""
module SymDiff

export Term, Const, Sym, PVar, Add, Mul, Pow, Fn,
       term, @term, to_expr, simplify, deriv, derivative, evaluate,
       Rule, @rule, match_pattern, substitute, rewrite, nodecount, is_size_decreasing

# =============================================================================
# Term representation
# =============================================================================

"""
    Term

Abstract supertype of every expression node.

Children are stored as `Term` (abstract) on purpose. A tree mixes node kinds, and
making each node parametric on its children's types would turn every expression
shape into a new type (and a new compilation). The cost is dynamic dispatch when
walking children; `evaluate` limits it with return-type assertions.
"""
abstract type Term end

"""
    Const(val)

Exact rational constant. `Rational{Int}` arithmetic is overflow-checked: it
throws `OverflowError` instead of wrapping around like `Int` arithmetic does.
"""
struct Const <: Term
    val::Rational{Int}
end
Const(x::AbstractFloat) = throw(ArgumentError(
    "Const takes exact numbers (Integer or Rational), got $(typeof(x)); " *
    "floats would make simplification inexact"))

"""Symbolic variable, e.g. `Sym(:x)`."""
struct Sym <: Term
    name::Symbol
end

"""Pattern variable, written `~name` inside `@term`/`@rule`. Matches any term."""
struct PVar <: Term
    name::Symbol
end

"""
    Add(args)

n-ary sum. Canonical form: at least two args, no `Add` among them, at most one
`Const` (first, nonzero), like terms combined, the rest sorted by `isless` of
their non-constant part.
"""
struct Add <: Term
    args::Vector{Term}
end

"""
    Mul(args)

n-ary product. Canonical form: at least two args, no `Mul` among them, at most
one `Const` (first, not 0 or 1), one factor per base, factors sorted by base.
"""
struct Mul <: Term
    args::Vector{Term}
end

"""`Pow(base, exp)`: `base ^ exp`."""
struct Pow <: Term
    base::Term
    exp::Term
end

"""
    Fn{F}(arg)
    Fn(f, arg)

Application of a known unary function. The function is part of the *type*
(`Fn{typeof(sin)}`), so derivative rules are methods chosen by dispatch rather
than branches of an `if` chain.
"""
struct Fn{F} <: Term
    arg::Term
end
Fn(f::F, arg::Term) where {F<:Function} = Fn{F}(arg)

"""The Julia function an `Fn` node applies."""
func(::Fn{F}) where {F} = F.instance

# Structural equality. The default `==` on a struct is `===`, which compares
# `Vector` fields by identity, so two separately built `Add`s would differ.
# `hash` must agree with `==`, or `Dict`/`Set` of terms silently break.
Base.:(==)(a::Add, b::Add) = a.args == b.args
Base.:(==)(a::Mul, b::Mul) = a.args == b.args
Base.:(==)(a::Pow, b::Pow) = a.base == b.base && a.exp == b.exp
Base.:(==)(a::Fn{F}, b::Fn{F}) where {F} = a.arg == b.arg
Base.hash(t::Add, h::UInt) = hash(t.args, hash(:Add, h))
Base.hash(t::Mul, h::UInt) = hash(t.args, hash(:Mul, h))
Base.hash(t::Pow, h::UInt) = hash(t.exp, hash(t.base, hash(:Pow, h)))
Base.hash(t::Fn, h::UInt) = hash(t.arg, hash(nameof(func(t)), h))

# A total order on terms, used to sort arguments into canonical order.
typerank(::Const) = 0
typerank(::Sym) = 1
typerank(::Pow) = 2
typerank(::Mul) = 3
typerank(::Add) = 4
typerank(::Fn) = 5
typerank(::PVar) = 6

Base.isless(a::Term, b::Term) = typerank(a) < typerank(b)
Base.isless(a::Const, b::Const) = a.val < b.val
Base.isless(a::Sym, b::Sym) = a.name < b.name
Base.isless(a::PVar, b::PVar) = a.name < b.name
Base.isless(a::Pow, b::Pow) = a.base == b.base ? isless(a.exp, b.exp) : isless(a.base, b.base)
Base.isless(a::Mul, b::Mul) = lexless(a.args, b.args)
Base.isless(a::Add, b::Add) = lexless(a.args, b.args)
function Base.isless(a::Fn{F}, b::Fn{G}) where {F,G}
    F === G && return isless(a.arg, b.arg)
    return nameof(F.instance) < nameof(G.instance)
end

function lexless(xs::Vector{Term}, ys::Vector{Term})
    for (a, b) in zip(xs, ys)
        a == b || return isless(a, b)
    end
    return length(xs) < length(ys)
end

# =============================================================================
# Building terms: operators, Expr -> Term, Term -> Expr
# =============================================================================

# Operators build raw (unsimplified) trees. Extending Base operators for our
# own type `Term` is not type piracy: we own one of the argument types.
Base.:+(a::Term, b::Term) = Add(Term[a, b])
Base.:*(a::Term, b::Term) = Mul(Term[a, b])
Base.:^(a::Term, b::Term) = Pow(a, b)
Base.:-(a::Term) = Mul(Term[Const(-1), a])
Base.:-(a::Term, b::Term) = a + (-b)
Base.:/(a::Term, b::Term) = a * Pow(b, Const(-1))
for op in (:+, :*, :^, :-, :/), N in (:Integer, :Rational)
    @eval Base.$op(a::Term, b::$N) = $op(a, Const(b))
    @eval Base.$op(a::$N, b::Term) = $op(Const(a), b)
end
for f in (:sin, :cos, :exp, :log)
    @eval Base.$f(t::Term) = Fn($f, t)
end

const FUNCTIONS = (sin = sin, cos = cos, exp = exp, log = log)

"""
    term(ex) -> Term

Convert a quoted Julia expression into a `Term`. Supports `+ - * / ^ //`, the
functions `sin cos exp log`, integer and rational literals, symbols, and pattern
variables `~name`. Anything else throws `ArgumentError`.

A small `if` chain on the operator symbol is the right tool here: the operator
is a runtime value, and dispatching on `Val(op)` would only move the branch
into the method table at extra cost.
"""
term(t::Term) = t
term(x::Union{Integer,Rational}) = Const(x)
term(x::AbstractFloat) = Const(x)          # throws a helpful ArgumentError
term(s::Symbol) = Sym(s)
function term(ex::Expr)
    ex.head === :call || throw(ArgumentError("unsupported syntax `$(ex.head)` in $ex"))
    op = ex.args[1]
    if op === :~
        name = ex.args[2]
        name isa Symbol || throw(ArgumentError("pattern variable must be a name: $ex"))
        return PVar(name)
    end
    args = Term[term(a) for a in ex.args[2:end]]
    if op === :+
        return length(args) == 1 ? args[1] : Add(args)
    elseif op === :*
        return Mul(args)
    elseif op === :-
        return length(args) == 1 ? -args[1] : args[1] - args[2]
    elseif op === :/
        return args[1] / args[2]
    elseif op === :^
        return Pow(args[1], args[2])
    elseif op === :(//)
        a, b = args
        return (a isa Const && b isa Const) ? Const(a.val // b.val) : a / b
    elseif op isa Symbol && haskey(FUNCTIONS, op) && length(args) == 1
        return Fn(FUNCTIONS[op], args[1])
    end
    throw(ArgumentError("unsupported operator `$op` in $ex"))
end

"""
    @term ex

Build a `Term` from Julia syntax: `@term x^2 + sin(x)`. Names become `Sym`s; they
do not need to be defined variables.

Precedence is Julia's: `~u^2` parses as `~(u^2)`, so write `(~u)^2`.
"""
macro term(ex)
    return :(term($(QuoteNode(ex))))
end

"""
    to_expr(t) -> Union{Expr,Symbol,Integer}

Inverse of `term` (on canonical terms): `term(to_expr(t)) == t`.
"""
to_expr(c::Const) = isone(denominator(c.val)) ? numerator(c.val) :
                    Expr(:call, :(//), numerator(c.val), denominator(c.val))
to_expr(s::Sym) = s.name
to_expr(p::PVar) = Expr(:call, :~, p.name)
to_expr(t::Add) = Expr(:call, :+, map(to_expr, t.args)...)
to_expr(t::Mul) = Expr(:call, :*, map(to_expr, t.args)...)
to_expr(t::Pow) = Expr(:call, :^, to_expr(t.base), to_expr(t.exp))
to_expr(t::Fn) = Expr(:call, nameof(func(t)), to_expr(t.arg))

Base.show(io::IO, t::Term) = print(io, to_expr(t))

"""Number of nodes in a term (every node counts 1, including pattern variables)."""
nodecount(::Union{Const,Sym,PVar}) = 1
nodecount(t::Union{Add,Mul}) = 1 + sum(nodecount, t.args; init = 0)
nodecount(t::Pow) = 1 + nodecount(t.base) + nodecount(t.exp)
nodecount(t::Fn) = 1 + nodecount(t.arg)

# =============================================================================
# Canonical simplification
# =============================================================================
#
# `simplify` is structural recursion: it simplifies the children, then rebuilds
# the node with a smart constructor (`mk_add`, `mk_mul`, `mk_pow`, `mk_fn`) that
# assumes canonical children and returns a canonical node.
#
# Termination: `simplify` only recurses into strict subterms. The smart
# constructors recurse only on exponents (strict subterms of a `Pow`) and on
# bases of nested powers, so every recursive call is on a smaller term.
#
# Scope (honest): the canonical form is unique for a given input *after* the
# rules below, but the simplifier does not expand products, so `2(x+1)` and
# `2x+2` are different normal forms. It is not a decision procedure for equality
# of expressions. Rewrites such as `x * x^-1 -> 1` are valid wherever both sides
# are defined (the usual convention of computer-algebra systems).

"""Split a canonical term into (rational coefficient, non-constant rest)."""
function coeff_and_rest(t::Term)
    t isa Mul || return (1 // 1, t)
    first_factor = t.args[1]
    first_factor isa Const || return (1 // 1, t)
    rest = length(t.args) == 2 ? t.args[2] : Mul(t.args[2:end])
    return (first_factor.val, rest)
end

"""Base of a factor: `x` for both `x` and `x^n`."""
base_of(t::Pow) = t.base
base_of(t::Term) = t
exponent_of(t::Pow) = t.exp
exponent_of(::Term) = Const(1)

# HOLE: canonical_sum
"""
    mk_add(args::Vector{Term}) -> Term

Canonical sum of already-canonical `args`:

1. Flatten: an `Add` among `args` contributes its own arguments.
2. Fold all `Const`s into one rational constant `c`.
3. Write every other summand as `k * rest` (see `coeff_and_rest`) and combine
   summands with equal `rest` by adding their `k`s. Drop those whose `k` is 0.
4. Rebuild each summand as `rest` (when `k == 1`) or `mk_mul(Term[Const(k), rest])`,
   in increasing `isless` order of `rest`.
5. Return `Const(c)` if nothing else is left; the single summand if `c == 0` and
   only one is left; otherwise `Add` with `Const(c)` first (omitted when `c == 0`).

Examples: `x + x -> 2x`, `3x + y - 3x -> y`, `1 + x + 2 -> 3 + x`.
"""
function mk_add(args::Vector{Term})
    flat = Term[]
    for a in args
        a isa Add ? append!(flat, a.args) : push!(flat, a)
    end
    c = 0 // 1
    parts = Tuple{Term,Rational{Int}}[]          # (rest, coefficient)
    for a in flat
        if a isa Const
            c += a.val
        else
            k, rest = coeff_and_rest(a)
            push!(parts, (rest, k))
        end
    end
    sort!(parts; by = first)
    summands = Term[]
    i = firstindex(parts)
    while i <= lastindex(parts)
        rest, k = parts[i]
        j = i + 1
        while j <= lastindex(parts) && parts[j][1] == rest
            k += parts[j][2]
            j += 1
        end
        iszero(k) || push!(summands, isone(k) ? rest : mk_mul(Term[Const(k), rest]))
        i = j
    end
    isempty(summands) && return Const(c)
    iszero(c) && length(summands) == 1 && return summands[1]
    return Add(iszero(c) ? summands : Term[Const(c); summands])
end

"""
    mk_mul(args::Vector{Term}) -> Term

Canonical product of already-canonical `args`: flatten nested products, fold
constants, merge factors with equal base by adding exponents, sort by base.
"""
function mk_mul(args::Vector{Term})
    flat = Term[]
    for a in args
        a isa Mul ? append!(flat, a.args) : push!(flat, a)
    end
    c = 1 // 1
    parts = Tuple{Term,Term}[]                   # (base, exponent)
    for a in flat
        if a isa Const
            c *= a.val
        else
            push!(parts, (base_of(a), exponent_of(a)))
        end
    end
    iszero(c) && return Const(0)
    sort!(parts; by = first)
    factors = Term[]
    i = firstindex(parts)
    while i <= lastindex(parts)
        b = parts[i][1]
        exps = Term[parts[i][2]]
        j = i + 1
        while j <= lastindex(parts) && parts[j][1] == b
            push!(exps, parts[j][2])
            j += 1
        end
        p = mk_pow(b, length(exps) == 1 ? exps[1] : mk_add(exps))
        p isa Const ? (c *= p.val) : push!(factors, p)
        i = j
    end
    iszero(c) && return Const(0)
    isempty(factors) && return Const(c)
    isone(c) && length(factors) == 1 && return factors[1]
    return Mul(isone(c) ? factors : Term[Const(c); factors])
end

"""
    mk_pow(b, e) -> Term

`x^0 -> 1`, `x^1 -> x`, `1^e -> 1`, integer powers of constants are folded, and
`(x^a)^n -> x^(a*n)` only for *integer* `n`. For non-integer `n` that rewrite is
unsound: `(x^2)^(1//2)` is `|x|`, not `x`.
"""
function mk_pow(b::Term, e::Term)
    if e isa Const
        iszero(e.val) && return Const(1)
        isone(e.val) && return b
        if isinteger(e.val)
            b isa Const && return fold_pow(b, Int(e.val))
            b isa Pow && return mk_pow(b.base, mk_mul(Term[b.exp, e]))
        end
    end
    b == Const(1) && return Const(1)
    return Pow(b, e)
end

function fold_pow(b::Const, n::Int)
    iszero(b.val) && n < 0 && return Pow(b, Const(n))   # keep 0^-n unevaluated
    try
        return Const(b.val^n)
    catch err
        err isa OverflowError || rethrow()
        return Pow(b, Const(n))                         # too large to fold exactly
    end
end

# Exact constant folding only; `log(exp(u)) -> u` is sound over the reals,
# `exp(log(u)) -> u` is not (fails for u <= 0) and is deliberately absent.
mk_fn(f::Function, a::Term) = Fn(f, a)
mk_fn(::typeof(log), a::Fn{typeof(exp)}) = a.arg
mk_fn(::typeof(sin), a::Const) = iszero(a.val) ? Const(0) : Fn(sin, a)
mk_fn(::typeof(cos), a::Const) = iszero(a.val) ? Const(1) : Fn(cos, a)
mk_fn(::typeof(exp), a::Const) = iszero(a.val) ? Const(1) : Fn(exp, a)
mk_fn(::typeof(log), a::Const) = isone(a.val) ? Const(0) : Fn(log, a)

"""
    simplify(t) -> Term

Canonical form of `t` (see the comment above `coeff_and_rest` for its scope).
Idempotent: `simplify(simplify(t)) == simplify(t)`.
"""
simplify(t::Union{Const,Sym,PVar}) = t
simplify(t::Add) = mk_add(Term[simplify(a) for a in t.args])
simplify(t::Mul) = mk_mul(Term[simplify(a) for a in t.args])
simplify(t::Pow) = mk_pow(simplify(t.base), simplify(t.exp))
simplify(t::Fn) = mk_fn(func(t), simplify(t.arg))

# =============================================================================
# Differentiation: one method per node kind, chosen by multiple dispatch
# =============================================================================

"""
    deriv(t, x::Sym) -> Term

Raw (unsimplified) derivative of `t` with respect to `x`. Use `derivative` for
the simplified result. Never mutates `t`.
"""
deriv(::Const, ::Sym) = Const(0)
deriv(s::Sym, x::Sym) = Const(s == x ? 1 : 0)
deriv(::PVar, ::Sym) = throw(ArgumentError("cannot differentiate a pattern variable"))
deriv(t::Add, x::Sym) = Add(Term[deriv(a, x) for a in t.args])

# HOLE: product_rule
"""
    deriv(t::Mul, x::Sym) -> Term

n-ary product rule: d(a₁·a₂·…·aₙ)/dx = Σᵢ a₁·…·(daᵢ/dx)·…·aₙ, as an `Add` of
`n` `Mul`s. Must not mutate `t` (or `t.args`).
"""
function deriv(t::Mul, x::Sym)
    summands = Term[]
    for i in eachindex(t.args)
        factors = copy(t.args)          # copy: assigning t.args would alias the input
        factors[i] = deriv(t.args[i], x)
        push!(summands, Mul(factors))
    end
    return Add(summands)
end

function deriv(t::Pow, x::Sym)
    b, e = t.base, t.exp
    if e isa Const                       # power rule
        return Mul(Term[e, Pow(b, Const(e.val - 1)), deriv(b, x)])
    end
    # general case: d(b^e) = b^e * (e' * log(b) + e * b' / b)
    return Mul(Term[t, Add(Term[Mul(Term[deriv(e, x), Fn(log, b)]),
                                Mul(Term[e, deriv(b, x), Pow(b, Const(-1))])])])
end

# HOLE: chain_rule
"""
    deriv(t::Fn{F}, x::Sym) -> Term

Chain rule: d f(u)/dx = f'(u) · du/dx. The outer derivative f'(u) is `dfn(f, u)`,
where `f = func(t)` and `u = t.arg`.
"""
function deriv(t::Fn{F}, x::Sym) where {F}
    return Mul(Term[dfn(func(t), t.arg), deriv(t.arg, x)])
end

"""`dfn(f, u)`: the outer derivative f'(u), one method per supported function."""
dfn(::typeof(sin), u::Term) = Fn(cos, u)
dfn(::typeof(cos), u::Term) = Mul(Term[Const(-1), Fn(sin, u)])
dfn(::typeof(exp), u::Term) = Fn(exp, u)
dfn(::typeof(log), u::Term) = Pow(u, Const(-1))

"""
    derivative(t, x) -> Term

Simplified derivative: `simplify(deriv(t, x))`. `x` may be a `Sym` or a `Symbol`.
"""
derivative(t::Term, x::Sym) = simplify(deriv(t, x))
derivative(t::Term, x::Symbol) = derivative(t, Sym(x))

# =============================================================================
# Numerical evaluation
# =============================================================================

"""
    evaluate(t, env::AbstractDict{Symbol,T}) -> T

Evaluate `t` with variables taken from `env`. With `T = Rational{BigInt}` the
result is exact for polynomial and rational-function terms. Each recursive call
is asserted `::T` so the result type is inferred as `T` even though children
are dispatched dynamically.
"""
evaluate(c::Const, ::AbstractDict{Symbol,T}) where {T<:Number} = convert(T, c.val)
evaluate(s::Sym, env::AbstractDict{Symbol,T}) where {T<:Number} = env[s.name]::T
evaluate(p::PVar, ::AbstractDict{Symbol,<:Number}) =
    throw(ArgumentError("cannot evaluate pattern variable ~$(p.name)"))
function evaluate(t::Add, env::AbstractDict{Symbol,T}) where {T<:Number}
    s = zero(T)
    for a in t.args
        s += evaluate(a, env)::T
    end
    return s
end
function evaluate(t::Mul, env::AbstractDict{Symbol,T}) where {T<:Number}
    p = one(T)
    for a in t.args
        p *= evaluate(a, env)::T
    end
    return p
end
function evaluate(t::Pow, env::AbstractDict{Symbol,T}) where {T<:Number}
    b = evaluate(t.base, env)::T
    e = t.exp
    if e isa Const && isinteger(e.val)
        return b^Int(e.val)
    end
    return b^(evaluate(e, env)::T)
end
evaluate(t::Fn, env::AbstractDict{Symbol,T}) where {T<:Number} = func(t)(evaluate(t.arg, env)::T)

# =============================================================================
# Pattern matching and rewriting
# =============================================================================

const Bindings = Dict{Symbol,Term}

"""
    match_pattern(pattern, t, b = Bindings()) -> Union{Bindings,Nothing}

One-way unification: find bindings for the pattern variables in `pattern` such
that substituting them gives `t`, extending the bindings `b`. Returns `nothing`
when there is none. `b` is never mutated.

Matching is positional on the arguments of `Add`/`Mul` (no associative-
commutative matching), so write patterns in canonical argument order.
"""
match_pattern(p::Term, t::Term) = match_pattern(p, t, Bindings())
match_pattern(::Term, ::Term, ::Bindings) = nothing          # different node kinds
match_pattern(p::Const, t::Const, b::Bindings) = p == t ? b : nothing
match_pattern(p::Sym, t::Sym, b::Bindings) = p == t ? b : nothing
match_pattern(p::Fn{F}, t::Fn{F}, b::Bindings) where {F} = match_pattern(p.arg, t.arg, b)
match_pattern(p::Add, t::Add, b::Bindings) = match_args(p.args, t.args, b)
match_pattern(p::Mul, t::Mul, b::Bindings) = match_args(p.args, t.args, b)
function match_pattern(p::Pow, t::Pow, b::Bindings)
    b1 = match_pattern(p.base, t.base, b)::Union{Nothing,Bindings}
    b1 === nothing && return nothing
    return match_pattern(p.exp, t.exp, b1)::Union{Nothing,Bindings}
end

# HOLE: pvar_binding
"""
    match_pattern(p::PVar, t::Term, b::Bindings) -> Union{Bindings,Nothing}

A pattern variable matches any term, but consistently: if `p.name` is already
bound in `b`, it matches only a term equal to the bound one (then return `b`);
otherwise return a *copy* of `b` extended with `p.name => t`. Never mutate `b`.
"""
function match_pattern(p::PVar, t::Term, b::Bindings)
    if haskey(b, p.name)
        return b[p.name] == t ? b : nothing
    end
    extended = copy(b)
    extended[p.name] = t
    return extended
end

function match_args(ps::Vector{Term}, ts::Vector{Term}, b::Bindings)
    length(ps) == length(ts) || return nothing
    current = b
    for (p, t) in zip(ps, ts)
        next = match_pattern(p, t, current)::Union{Nothing,Bindings}
        next === nothing && return nothing
        current = next
    end
    return current
end

"""Replace every pattern variable in `t` by its binding in `b` (`KeyError` if unbound)."""
substitute(p::PVar, b::Bindings) = b[p.name]
substitute(t::Union{Const,Sym}, ::Bindings) = t
substitute(t::Term, b::Bindings) = map_children(c -> substitute(c, b), t)

"""Rebuild `t` with `f` applied to each direct child."""
map_children(f, t::Union{Const,Sym,PVar}) = t
map_children(f, t::Add) = Add(Term[f(a) for a in t.args])
map_children(f, t::Mul) = Mul(Term[f(a) for a in t.args])
map_children(f, t::Pow) = Pow(f(t.base), f(t.exp))
map_children(f, t::Fn) = Fn(func(t), f(t.arg))

"""Occurrences of each pattern variable in `t`."""
function varcounts(t::Term)
    counts = Dict{Symbol,Int}()
    count_vars!(counts, t)
    return counts
end
count_vars!(counts::Dict{Symbol,Int}, p::PVar) = (counts[p.name] = get(counts, p.name, 0) + 1; counts)
count_vars!(counts::Dict{Symbol,Int}, ::Union{Const,Sym}) = counts
count_vars!(counts::Dict{Symbol,Int}, t::Union{Add,Mul}) = (foreach(a -> count_vars!(counts, a), t.args); counts)
count_vars!(counts::Dict{Symbol,Int}, t::Pow) = (count_vars!(counts, t.base); count_vars!(counts, t.exp))
count_vars!(counts::Dict{Symbol,Int}, t::Fn) = count_vars!(counts, t.arg)

"""
    Rule(lhs, rhs)
    @rule lhs => rhs

A rewrite rule `lhs -> rhs`. Pattern variables (`~a`) used in `rhs` must occur in
`lhs`. The lhs is used as written (positional matching).
"""
struct Rule
    lhs::Term
    rhs::Term
    function Rule(lhs::Term, rhs::Term)
        unbound = setdiff(keys(varcounts(rhs)), keys(varcounts(lhs)))
        isempty(unbound) || throw(ArgumentError(
            "rule rhs uses unbound pattern variables: $(sort!(collect(unbound)))"))
        return new(lhs, rhs)
    end
end

Base.show(io::IO, r::Rule) = print(io, r.lhs, " => ", r.rhs)

macro rule(ex)
    (ex isa Expr && ex.head === :call && ex.args[1] === :(=>)) ||
        throw(ArgumentError("@rule expects `lhs => rhs`"))
    return :(Rule(term($(QuoteNode(ex.args[2]))), term($(QuoteNode(ex.args[3])))))
end

# HOLE: size_measure
"""
    is_size_decreasing(r::Rule) -> Bool

`true` when *every* instance of `r` strictly shrinks the term's `nodecount`, which
proves that rewriting with a set of such rules terminates under any strategy.

Condition: `nodecount(r.lhs) > nodecount(r.rhs)` **and** every pattern variable
occurs in `r.rhs` at most as many times as in `r.lhs` (a variable duplicated on
the right can be bound to an arbitrarily large term).

Why it suffices: for a substitution σ, size(lσ) − size(rσ) =
(size(l) − size(r)) + Σᵥ (occₗ(v) − occᵣ(v))·(size(σv) − 1) > 0, and replacing a
subterm by a smaller one shrinks the whole term.
"""
function is_size_decreasing(r::Rule)
    nodecount(r.lhs) > nodecount(r.rhs) || return false
    lhs_counts = varcounts(r.lhs)
    return all(get(lhs_counts, v, 0) >= n for (v, n) in varcounts(r.rhs))
end

"""
    rewrite(t, rules; maxsteps = 10_000) -> Term

Rewrite `t` to a normal form with `rules` (innermost strategy, see
`rewrite_budgeted!`). Throws `ErrorException` after `maxsteps` rule applications:
a guard against non-terminating rule sets, not a termination proof (for that, see
`is_size_decreasing`). Does not call `simplify`.
"""
rewrite(t::Term, rules::Vector{Rule}; maxsteps::Int = 10_000) =
    rewrite_budgeted!(Ref(maxsteps), t, rules)

# HOLE: rewrite_innermost
"""
    rewrite_budgeted!(budget::Ref{Int}, t, rules) -> Term

Innermost rewriting. First rewrite every child of `t` (use `map_children`). Then
try the rules *in order* at the root; for the first whose `lhs` matches, spend one
step of `budget` (if `budget[]` would go below zero, throw
`error("rewrite: step budget exhausted")`), substitute the bindings into its
`rhs`, and rewrite *that result* again, because it may contain new redexes. If no
rule matches, return the term. Mutates only `budget`, which by Julia's
convention for `!` functions comes first.
"""
function rewrite_budgeted!(budget::Ref{Int}, t::Term, rules::Vector{Rule})
    t = map_children(c -> rewrite_budgeted!(budget, c, rules), t)
    for r in rules
        b = match_pattern(r.lhs, t)
        b === nothing && continue
        budget[] -= 1
        budget[] < 0 && error("rewrite: step budget exhausted")
        return rewrite_budgeted!(budget, substitute(r.rhs, b), rules)
    end
    return t
end

end # module
