module Classify

using Random, Statistics
import Flux

export load_split, FluxModel, train_flux, predict_flux

function load_split(rng, path; test_fraction = 0.3)
    lines = [l for l in Iterators.drop(eachline(path), 1) if !isempty(strip(l))]
    fields = [split(strip(l), ",") for l in lines]
    X = Float32[parse(Float32, f[i]) for i in 1:4, f in fields]
    y = [String(f[5]) for f in fields]
    tr = Int[]
    te = Int[]
    for c in sort(unique(y))
        idx = shuffle(rng, findall(==(c), y))
        k = round(Int, test_fraction * length(idx))
        append!(te, idx[1:k])
        append!(tr, idx[k+1:end])
    end
    return (Xtrain = X[:, tr], ytrain = y[tr], Xtest = X[:, te], ytest = y[te])
end

# The network sees the raw measurements: stem_mm (hundreds) swamps the rest.
struct FluxModel{C}
    chain::C
    classes::Vector{String}
    mu::Matrix{Float32}
    sigma::Matrix{Float32}
end

(m::FluxModel)(X) = m.chain(X)

function train_flux(rng, X, y; epochs = 200)
    classes = sort(unique(y))
    init = Flux.glorot_uniform(rng)
    chain = Flux.Chain(Flux.Dense(size(X, 1) => 16, Flux.relu; init = init),
                       Flux.Dense(16 => length(classes); init = init))
    Y = Flux.onehotbatch(y, classes)
    opt = Flux.setup(Flux.Adam(0.01), chain)
    for _ in 1:epochs
        g = Flux.gradient(c -> Flux.logitcrossentropy(c(X), Y), chain)
        Flux.update!(opt, chain, g[1])
    end
    return FluxModel(chain, classes, zeros(Float32, size(X, 1), 1), ones(Float32, size(X, 1), 1))
end

predict_flux(m::FluxModel, X) = m.classes[Flux.onecold(m(X))]

end
