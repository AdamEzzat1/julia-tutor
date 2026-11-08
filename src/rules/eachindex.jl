# JT005: `for i in 1:length(x)` assumes 1-based, linear indexing.

struct OneToLength <: Rule end

meta(::OneToLength) = RuleMeta(
    "JT005", "one-to-length-loop", "generic-indexing", ADVICE,
    "High as a bug claim: for a plain `Vector`, 1:length(x) is correct, which is " *
    "why this is ADVICE. It matters for generic code (OffsetArrays, views with " *
    "offset axes) and when the loop indexes a different array than the one measured.",
    "none (generic-programming advice)",
    ("Which indices does this loop visit, and are those guaranteed to be valid " *
     "indices of the array for every `AbstractArray`?",
     "`1:length(x)` assumes indices start at 1 and are linear. Arrays with other " *
     "axes exist, and the range is also easy to pair with the wrong array.",
     "Iterate the array's own indices: `for i in eachindex(x)` (or `axes(x, 1)`, " *
     "or `pairs(x)` when you need both index and value)."),
    ["eachindex", "axes(", "pairs("])

function check(r::OneToLength, ctx::FileContext)
    out = Finding[]
    walk(ctx.tree) do n
        kind(n) in (K"in", K"=") || return true
        p = n.parent
        (p !== nothing && kind(p) == K"iteration") || return true
        rng = kids(n)[end]
        (kind(rng) == K"call" && is_infix(rng)) || return true
        callee, args = call_parts(rng)
        (ident(callee) === :(:) && length(args) == 2) || return true
        lo, hi = args
        (kind(lo) == K"Integer" && lo.val == 1 && kind(hi) == K"call") || return true
        hcallee, hargs = call_parts(hi)
        if ident(hcallee) === :length && length(hargs) == 1
            push!(out, finding(r, ctx, rng, "loop over `1:length($(JS.sourcetext(hargs[1])))`"))
        elseif ident(hcallee) === :size && length(hargs) == 2
            push!(out, finding(r, ctx, rng, "loop over `1:size($(JS.sourcetext(hargs[1])), ...)`"))
        end
        true
    end
    return out
end
