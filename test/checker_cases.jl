# Per-rule fixtures. Every rule must have:
# * positive cases (the rule fires),
# * negative cases (near misses: the rule must stay silent),
# * at least one style pair: two different *correct* styles that both produce
#   zero findings from every rule (invariant 1: style tolerance).

const CASES = Dict{String,NamedTuple}(
    "JT001" => (
        positive = [
            "x = []",
            "function f()\n    v = []\n    push!(v, 1)\n    return v\nend",
            "d = Dict()",
        ],
        negative = [
            "x = Int[]",
            "x = [1, 2]",
            "x = Vector{Float64}()",
            "@test f() == []",
            "d = Dict{Symbol,Int}()",
            "d = Dict(:a => 1)",
        ],
        styles = [(
            "function squares(n)\n    out = Int[]\n    for i in 1:n\n        push!(out, i^2)\n    end\n    return out\nend",
            "squares(n) = [i^2 for i in 1:n]",
        )],
    ),
    "JT002" => (
        positive = [
            "struct P\n    x::Real\nend",
            "struct P\n    v::Vector\nend",
            "struct P\n    f::Function\nend",
            "struct P\n    a::Array{Float64}\nend",
            "struct P\n    z\nend",
            "mutable struct P\n    d::Dict\nend",
            "struct P\n    v::AbstractVector{Float64}\nend",
            "struct P\n    \"documented\"\n    x::Number\nend",
        ],
        negative = [
            "struct P\n    x::Float64\nend",
            "struct P{T<:Real}\n    x::T\nend",
            "abstract type Term end\nstruct Add <: Term\n    args::Vector{Term}\nend",
            "struct P\n    t::Term\nend",                      # user-defined abstract type: by design
            "struct P\n    v::Vector{Real}\nend",              # concrete container type
            "struct P\n    a::Array{Float64,2}\nend",
            "struct P\n    u::Union{Int,Nothing}\nend",
            "struct Real2\nend\nstruct P\n    x::Vector{Real2}\nend",
        ],
        styles = [(
            "struct Particle\n    x::Float64\n    v::Float64\nend",
            "struct Particle{T<:AbstractFloat}\n    x::T\n    v::T\nend",
        )],
    ),
    "JT003" => (
        positive = [
            "function scale(v, a)\n    v .= v .* a\nend",
            "function setfirst(v)\n    v[1] = 0\n    return v\nend",
            "function addone(v)\n    push!(v, 1)\nend",
            "function reset(p)\n    p.count = 0\nend",
            "bump(c) = (c[] += 1)",
        ],
        negative = [
            "function scale!(v, a)\n    v .= v .* a\nend",
            "function scaled(v, a)\n    return v .* a\nend",
            "function f(v)\n    v = copy(v)\n    v[1] = 0\n    return v\nend",
            "function f(v)\n    w = similar(v)\n    w[1] = 0\n    return w\nend",
            "function g(n)\n    out = Int[]\n    push!(out, n)\n    return out\nend",
            "function h(budget, t)\n    return run!(Ref(1), t)\nend",
        ],
        styles = [(
            "function normalize(v)\n    s = sum(v)\n    return v ./ s\nend",
            "function normalize(v)\n    s = sum(v)\n    return [x / s for x in v]\nend",
        )],
    ),
    "JT004" => (
        positive = [
            "function total!(v)\n    return sum(v)\nend",
            "double!(x) = 2x",
        ],
        negative = [
            "function total!(v)\n    v[1] = sum(v)\nend",
            "count!(c::Dict, k) = (c[k] = get(c, k, 0) + 1; c)\ncount!(c::Dict, ::Nothing) = c",
            "function fill_zero!(v)\n    fill!(v, 0)\nend",
            "function inc!(r)\n    r[] += 1\nend",
        ],
        styles = [(
            "function clamp01!(v)\n    for i in eachindex(v)\n        v[i] = clamp(v[i], 0, 1)\n    end\n    return v\nend",
            "clamp01!(v) = (v .= clamp.(v, 0, 1))",
        )],
    ),
    "JT005" => (
        positive = [
            "for i in 1:length(x)\n    println(x[i])\nend",
            "function f(A)\n    for j in 1:size(A, 2)\n    end\nend",
            "s = sum(x[i] for i in 1:length(x))",
            "for i = 1:length(x)\nend",
        ],
        negative = [
            "for i in eachindex(x)\nend",
            "for (i, v) in pairs(x)\nend",
            "for i in 1:n\nend",
            "for i in 2:length(x)\nend",
        ],
        styles = [(
            "function total(x)\n    s = zero(eltype(x))\n    for i in eachindex(x)\n        s += x[i]\n    end\n    return s\nend",
            "function total(x)\n    s = zero(eltype(x))\n    for v in x\n        s += v\n    end\n    return s\nend",
        )],
    ),
    "JT006" => (
        positive = [
            "@test 0.1 + 0.2 == 0.3",
            "if x == 0.5\nend",
            "@test f(x) != 1e-3",
            "y === -0.0",
        ],
        negative = [
            "@test isapprox(0.1 + 0.2, 0.3; rtol = 4eps())",
            "@test x == 1",
            "@test a ≈ b",
            "x < 0.5",
        ],
        styles = [(
            "@test isapprox(f(0.5), 0.25; rtol = 1e-12)",
            "@test f(0.5) ≈ 0.25 rtol = 1e-12",
        )],
    ),
    "JT007" => (
        positive = [
            "G = 9.81\nfunction fall(t)\n    return 0.5 * G * t^2\nend",
            "counter = 0\nfunction bump()\n    global counter\n    counter += 1\nend",
            "data = [1, 2]\nf() = sum(data)",
            "module M\nscale = 2.0\ng(x) = scale * x\nend",
        ],
        negative = [
            "const G = 9.81\nfunction fall(t)\n    return 0.5 * G * t^2\nend",
            "G = 9.81\nfunction fall(t, G)\n    return 0.5 * G * t^2\nend",
            "G = 1\nfunction f()\n    G = 2\n    return G\nend",
            "x = 1\nf(p) = p.x",
            "k = 1\nf() = g(; k = 2)",
            "G = 1\nf() = :G",
            "v = 1\nf(xs) = [v for v in xs]",
        ],
        styles = [(
            "const G = 9.81\nfall(t) = 0.5 * G * t^2",
            "fall(t; g = 9.81) = 0.5 * g * t^2",
        )],
    ),
)
