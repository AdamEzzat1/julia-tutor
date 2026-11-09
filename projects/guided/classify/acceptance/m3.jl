# Acceptance, milestone 3: train_mlj / predict_mlj and train_betaml / predict_betaml.
# One @testset per behaviour id.
using Classify, Test, Random
import MLJ

const FLOWERS = joinpath(@__DIR__, "data", "flowers.csv")

# Accuracy threshold 0.85, calibrated (not derived): over split seeds 1-12
# with training seeds 101-112 on the pinned MLJ 0.23.3 / DecisionTree 0.12.4
# and BetaML 0.14.0, the lowest test accuracy was 24/27 = 0.889 for the tree
# and 24/27 = 0.889 for the forest (margin 0.039, one sample of 27).
const MIN_ACCURACY = 0.85
const SEEDS = 1:4

acc(yhat, y) = count(yhat .== y) / length(y)

"""Components of a model: its property values (a pipeline's are its steps)."""
parts(model) = [getproperty(model, n) for n in propertynames(model)]

@testset "mlj-pipeline" begin
    d = load_split(Xoshiro(1), FLOWERS)
    mach = train_mlj(Xoshiro(2), d.Xtrain, d.ytrain)
    @test mach isa MLJ.Machine
    @test any(x -> x isa MLJ.Standardizer, parts(mach.model))
    @test any(x -> nameof(typeof(x)) === :DecisionTreeClassifier, parts(mach.model))
    p = predict_mlj(mach, d.Xtest)
    @test p isa Vector{String}
    @test length(p) == length(d.ytest)
    for s in SEEDS
        d = load_split(Xoshiro(s), FLOWERS)
        mach = train_mlj(Xoshiro(100 + s), d.Xtrain, d.ytrain)
        @test acc(predict_mlj(mach, d.Xtest), d.ytest) >= MIN_ACCURACY
    end
end

# Labels drawn at random: a forest fitted to them depends on its random
# draws, so two forests from different random streams disagree on some of
# these 40 points (calibrated: seed s against seed s + 10, s = 1-6, they
# disagreed on 4 to 8 of 40), while two from the same seed agree everywhere.
function noise(rng)
    X = randn(rng, Float32, 4, 40)
    y = rand(rng, ["p", "q"], 40)
    return X, y
end

@testset "betaml-model" begin
    d = load_split(Xoshiro(1), FLOWERS)
    model = train_betaml(Xoshiro(2), d.Xtrain, d.ytrain)
    p = predict_betaml(model, d.Xtest)
    @test p isa Vector{String}
    @test length(p) == length(d.ytest)
    X, y = noise(Xoshiro(11))
    Xnew, _ = noise(Xoshiro(12))
    a = predict_betaml(train_betaml(Xoshiro(3), X, y), Xnew)
    b = predict_betaml(train_betaml(Xoshiro(3), X, y), Xnew)
    c = predict_betaml(train_betaml(Xoshiro(4), X, y), Xnew)
    @test a == b
    @test a != c
    for s in SEEDS
        d = load_split(Xoshiro(s), FLOWERS)
        model = train_betaml(Xoshiro(100 + s), d.Xtrain, d.ytrain)
        @test acc(predict_betaml(model, d.Xtest), d.ytest) >= MIN_ACCURACY
    end
end
