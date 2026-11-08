# JT002: struct fields whose declared type is abstract or an incomplete UnionAll.

struct AbstractFieldType <: Rule end

meta(::AbstractFieldType) = RuleMeta(
    "JT002", "abstract-field-type", "concrete-field-types", WARN,
    "Only Base's abstract numeric/container/function types and unparameterized " *
    "Base containers are flagged, never user-defined abstract types: a recursive " *
    "tree whose children are `::Term` is the right design. Untyped fields are " *
    "flagged (they are `::Any`); that is a false positive for rarely-read metadata. " *
    "Names shadowed by a type defined in the same file and struct type parameters " *
    "are excluded.",
    "explain: inferred return types of functions reading the field",
    ("When Julia compiles code that reads this field, what does it know about " *
     "the value's type from the declaration alone?",
     "A field declared with an abstract type (or no type, which means `Any`) can " *
     "hold values of many concrete types, so every read must check the type at " *
     "run time, and the value is stored boxed.",
     "Use a concrete type (`x::Float64`, `v::Vector{Float64}`) or make the struct " *
     "parametric: `struct P{T<:Real}; x::T; end`."),
    ["Float64", "{T", "where T", "::T"])

const ABSTRACT_BASE_TYPES = Set([
    :Any, :Number, :Real, :Integer, :Signed, :Unsigned, :AbstractFloat,
    :AbstractIrrational, :AbstractString, :AbstractChar, :AbstractArray,
    :AbstractVector, :AbstractMatrix, :AbstractVecOrMat, :AbstractRange,
    :AbstractUnitRange, :AbstractDict, :AbstractSet, :Function, :IO])

# Parametric Base types that are not concrete without all of their parameters.
const PARAMETRIC_BASE_ARITY = Dict(
    :Vector => 1, :Matrix => 1, :Array => 2, :Dict => 2, :Set => 1, :Rational => 1,
    :Complex => 1, :Ref => 1, :Pair => 2, :UnitRange => 1, :StepRange => 2)

function check(r::AbstractFieldType, ctx::FileContext)
    out = Finding[]
    walk(ctx.tree) do n
        kind(n) == K"struct" || return true
        cs = kids(n)
        length(cs) >= 2 || return true
        tparams = struct_type_params(cs[1])
        for field in kids(cs[2])
            check_field!(out, r, ctx, unwrap_field(field), tparams)
        end
        return false
    end
    return out
end

function unwrap_field(f::SyntaxNode)
    while kind(f) in (K"doc", K"const") && !isempty(kids(f))
        f = kids(f)[end]
    end
    return f
end

function struct_type_params(head::SyntaxNode)
    out = Set{Symbol}()
    h = head
    kind(h) == K"<:" && (h = kids(h)[1])
    if kind(h) == K"curly"
        for p in kids(h)[2:end]
            nm = kind(p) == K"<:" ? ident(kids(p)[1]) : ident(p)
            nm === nothing || push!(out, nm)
        end
    end
    return out
end

function check_field!(out::Vector{Finding}, r::AbstractFieldType, ctx::FileContext,
                      f::SyntaxNode, tparams::Set{Symbol})
    k = kind(f)
    if k == K"Identifier"
        push!(out, finding(r, ctx, f, "field `$(f.val)` has no type, so it is `::Any`"))
    elseif k == K"::" && length(kids(f)) == 2
        name, T = kids(f)
        why = abstract_reason(T, tparams, ctx.type_names)
        why === nothing ||
            push!(out, finding(r, ctx, f, "field `$(ident(name))::$(JS.sourcetext(T))` $why"))
    end
    return out
end

function abstract_reason(T::SyntaxNode, tparams::Set{Symbol}, local_types::Set{Symbol})
    if kind(T) == K"Identifier"
        nm = T.val::Symbol
        (nm in tparams || nm in local_types) && return nothing
        nm in ABSTRACT_BASE_TYPES && return "is an abstract type"
        haskey(PARAMETRIC_BASE_ARITY, nm) && return "is missing its type parameters (not a concrete type)"
    elseif kind(T) == K"curly"
        head = ident(kids(T)[1])
        (head === nothing || head in local_types) && return nothing
        head in ABSTRACT_BASE_TYPES && return "is an abstract type"
        nparams = length(kids(T)) - 1
        head === :Array && nparams == 1 &&
            return "is missing the dimension parameter (not a concrete type)"
        head !== :Array && nparams < get(PARAMETRIC_BASE_ARITY, head, 0) &&
            return "is missing type parameters (not a concrete type)"
    end
    return nothing
end
