# JT006: exact comparison against a floating-point literal.

struct FloatLiteralEquality <: Rule end

meta(::FloatLiteralEquality) = RuleMeta(
    "JT006", "float-literal-equality", "floating-point-comparison", WARN,
    "Only comparisons with a float *literal* are seen; `a == b` between two float " *
    "variables needs types and is not flagged. `x == 0.0` is sometimes exactly what " *
    "is meant (guarding a division), so outside `@test` this is ADVICE; inside " *
    "`@test` it is WARN because tests must state a tolerance (invariant 9).",
    "none (the failure is numerical, not measurable statically)",
    ("Is the value on the other side of this comparison computed with rounding? " *
     "If so, how close to the literal is it guaranteed to be?",
     "Most decimal literals (0.1, 0.3) are not exactly representable in binary, " *
     "and computed floats carry rounding error, so exact equality can fail for a " *
     "correct computation (try `0.1 + 0.2 == 0.3`).",
     "Compare with a tolerance you can justify: `isapprox(a, b; rtol = ...)` or " *
     "`a ≈ b`, and write down where the tolerance comes from."),
    ["isapprox", "≈", "rtol", "atol"])

const EQ_OPS = (:(==), :(!=), :(===), :(!==), :≠)

is_float_literal(n::SyntaxNode) = kind(n) in (K"Float", K"Float32")

function inside_test_macro(n::SyntaxNode)
    for a in ancestors(n)
        macro_name(a) in (Symbol("@test"), Symbol("@test_broken")) && return true
    end
    return false
end

function check(r::FloatLiteralEquality, ctx::FileContext)
    out = Finding[]
    walk(ctx.tree) do n
        (kind(n) == K"call" && is_infix(n)) || return true
        callee, args = call_parts(n)
        (ident(callee) in EQ_OPS && length(args) == 2) || return true
        lit = findfirst(is_float_literal, args)
        lit === nothing && return true
        in_test = inside_test_macro(n)
        msg = "exact `$(ident(callee))` comparison with float literal `$(JS.sourcetext(args[lit]))`" *
              (in_test ? " in a test" : "")
        push!(out, finding(r, ctx, n, msg; severity = in_test ? WARN : ADVICE))
        true
    end
    return out
end
