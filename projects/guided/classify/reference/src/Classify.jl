"""
    Classify

Reference solution of the `classify` guided project: one seeded, stratified
train/test split of a small flower data set, the same classification task
solved with Flux.jl (a two-layer network), MLJ.jl (a standardiser and a
decision tree in a pipeline) and BetaML.jl (a random forest), and one table
comparing them.

Every function that shuffles, initialises or samples takes an `rng` first.
"""
module Classify

using Random, Statistics
import Flux
import MLJ
import BetaML
import MLJDecisionTreeInterface: DecisionTreeClassifier

export load_split, FluxModel, train_flux, predict_flux, train_mlj, predict_mlj,
       train_betaml, predict_betaml, compare

# ---- milestone 1: data and a reproducible split ------------------------------------------------

"""
    read_flowers(path) -> (X::Matrix{Float32}, y::Vector{String})

Parse a comma-separated file with a header line: every column but the last
is a measurement, the last is the label. `X` has one column per sample.
"""
function read_flowers(path::AbstractString)
    lines = [strip(l) for l in Iterators.drop(eachline(path), 1)]
    rows = [split(l, ',') for l in lines if !isempty(l)]
    nf = length(rows[1]) - 1
    X = [parse(Float32, r[i]) for i in 1:nf, r in rows]   # features down, samples across
    y = [String(r[end]) for r in rows]
    return X, y
end

"""
    load_split(rng, path; test_fraction = 0.3) -> (; Xtrain, ytrain, Xtest, ytest)

Read `path` and split it into train and test sets class by class, so each
class keeps its share: of a class with `n` samples, `round(Int, test_fraction * n)`
go to the test set. `X` matrices are `Float32` with one column per sample.
"""
function load_split(rng::AbstractRNG, path::AbstractString; test_fraction::Real = 0.3)
    0 < test_fraction < 1 || throw(ArgumentError("test_fraction must be in (0, 1), got $test_fraction"))
    X, y = read_flowers(path)
    train = Int[]
    test = Int[]
    for c in sort(unique(y))
        idx = shuffle(rng, findall(==(c), y))
        k = round(Int, test_fraction * length(idx))
        append!(test, idx[1:k])
        append!(train, idx[k+1:end])
    end
    return (Xtrain = X[:, train], ytrain = y[train], Xtest = X[:, test], ytest = y[test])
end

"""
    accuracy(yhat, y) -> Float64

The share of positions where `yhat` and `y` agree.
"""
function accuracy(yhat::AbstractVector, y::AbstractVector)
    length(yhat) == length(y) || throw(DimensionMismatch("$(length(yhat)) predictions for $(length(y)) labels"))
    return count(yhat .== y) / length(y)
end

# ---- milestone 2: a Flux network ---------------------------------------------------------------

"""
A trained network with what it needs to predict: the class list (sorted;
output row i is `classes[i]`) and the training set's feature means and
standard deviations, applied to every input.
"""
struct FluxModel{C}
    chain::C
    classes::Vector{String}
    mu::Matrix{Float32}
    sigma::Matrix{Float32}
end

"""The network's raw outputs (logits), one column per sample of `X`."""
(m::FluxModel)(X::AbstractMatrix) = m.chain((X .- m.mu) ./ m.sigma)

const HIDDEN = 16

"""
    train_flux(rng, X, y; epochs = 200) -> FluxModel

A network `Dense(features => 16, relu)`, `Dense(16 => classes)` initialised
from `rng`, trained full-batch with Adam (learning rate 0.01) on the
cross-entropy of the standardised features.
"""
function train_flux(rng::AbstractRNG, X::AbstractMatrix, y::AbstractVector; epochs::Integer = 200)
    classes = sort(unique(String.(y)))
    mu = mean(X; dims = 2)
    sigma = std(X; dims = 2) .+ eps(Float32)
    init = Flux.glorot_uniform(rng)
    chain = Flux.Chain(Flux.Dense(size(X, 1) => HIDDEN, Flux.relu; init = init),
                       Flux.Dense(HIDDEN => length(classes); init = init))
    model = FluxModel(chain, classes, Matrix{Float32}(mu), Matrix{Float32}(sigma))
    Xs = (X .- model.mu) ./ model.sigma
    Y = Flux.onehotbatch(y, classes)
    opt = Flux.setup(Flux.Adam(0.01), chain)
    for _ in 1:epochs
        grads = Flux.gradient(c -> Flux.logitcrossentropy(c(Xs), Y), chain)
        Flux.update!(opt, chain, grads[1])
    end
    return model
end

"""
    predict_flux(model, X) -> Vector{String}

The most likely class of each column of `X`.
"""
predict_flux(m::FluxModel, X::AbstractMatrix) = m.classes[Flux.onecold(m(X))]

# ---- milestone 3: MLJ and BetaML --------------------------------------------------------------

"""Samples as rows: the table MLJ wants, from Flux's columns."""
rows_table(X::AbstractMatrix) = MLJ.table(permutedims(Float64.(X)))

"""
    train_mlj(rng, X, y) -> MLJ.Machine

A machine for `Standardizer() |> DecisionTreeClassifier(rng = rng)`, fitted
on `X` (one column per sample) and labels `y`.
"""
function train_mlj(rng::AbstractRNG, X::AbstractMatrix, y::AbstractVector)
    pipe = MLJ.Standardizer() |> DecisionTreeClassifier(rng = rng)
    mach = MLJ.machine(pipe, rows_table(X), MLJ.categorical(String.(y)))
    MLJ.fit!(mach; verbosity = 0)
    return mach
end

"""
    predict_mlj(mach, X) -> Vector{String}

The most likely class of each column of `X`.
"""
predict_mlj(mach, X::AbstractMatrix) = String.(MLJ.predict_mode(mach, rows_table(X)))

const N_TREES = 30

"""
    train_betaml(rng, X, y) -> BetaML.RandomForestEstimator

A random forest of 30 trees drawing from `rng`, fitted on `X` (one column
per sample) and labels `y`.
"""
function train_betaml(rng::AbstractRNG, X::AbstractMatrix, y::AbstractVector)
    model = BetaML.RandomForestEstimator(n_trees = N_TREES, rng = rng, verbosity = BetaML.NONE)
    BetaML.fit!(model, permutedims(Float64.(X)), String.(y))
    return model
end

"""
    predict_betaml(model, X) -> Vector{String}

The most likely class of each column of `X`.
"""
predict_betaml(model, X::AbstractMatrix) =
    String.(BetaML.mode(BetaML.predict(model, permutedims(Float64.(X)))))

# ---- milestone 4: the comparison --------------------------------------------------------------

"""
Size of a fitted model: trainable parameters (Flux), leaves of the tree
(MLJ), trees in the forest (BetaML).
"""
model_size(m::FluxModel) = sum(length, Flux.trainables(m.chain))
model_size(mach::MLJ.Machine) = length(MLJ.fitted_params(mach).decision_tree_classifier.raw_tree)
model_size(model::BetaML.RandomForestEstimator) = length(model.par.forest.trees)

"""Train with `train(rng)`, after one untimed warm-up call; (model, seconds)."""
function timed_fit(train, rng::AbstractRNG)
    train(Xoshiro(0))                 # warm-up: compiles every method the timed call runs
    t = time_ns()
    model = train(rng)
    return model, (time_ns() - t) / 1e9
end

"""
    compare(rng, path) -> Vector of (; library, accuracy, seconds, size)

Split `path` with `rng`, then train Flux, MLJ and BetaML in that order on the
training set, each with `rng` as the previous step left it, and score each on
the test set. One row per library, sorted by accuracy (highest first), then
by library name.
"""
function compare(rng::AbstractRNG, path::AbstractString)
    d = load_split(rng, path)
    libs = (("flux", r -> train_flux(r, d.Xtrain, d.ytrain), predict_flux),
            ("mlj", r -> train_mlj(r, d.Xtrain, d.ytrain), predict_mlj),
            ("betaml", r -> train_betaml(r, d.Xtrain, d.ytrain), predict_betaml))
    rows = map(libs) do (name, train, predict)
        model, seconds = timed_fit(train, rng)
        (library = name, accuracy = accuracy(predict(model, d.Xtest), d.ytest),
         seconds = seconds, size = model_size(model))
    end
    return sort!(collect(rows); by = r -> (-r.accuracy, r.library))
end

end # module Classify
