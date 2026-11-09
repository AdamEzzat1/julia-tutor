# Acceptance, milestone 2: train_flux and predict_flux. One @testset per behaviour id.
using Classify, Test, Random

const FLOWERS = joinpath(@__DIR__, "data", "flowers.csv")

# Accuracy threshold 0.85, calibrated (not derived): over split seeds 1-12
# with training seeds 101-112 on the pinned Flux 0.16.15, the reference's
# lowest test accuracy was 25/27 = 0.926 (2 errors); 0.85 allows 4 errors
# of 27 (margin 0.076). With only 5 epochs the same seeds gave 0.41 to 0.93,
# so the threshold does catch a network that has not learned.
const MIN_ACCURACY = 0.85
const SEEDS = 1:4

acc(yhat, y) = count(yhat .== y) / length(y)

"""A small separable data set with `k` classes named in reverse order of first appearance."""
function blobs(rng, k; n = 12)
    names = ["c$(k - i + 1)" for i in 1:k]          # c3, c2, c1: not sorted
    X = Matrix{Float32}(undef, 3, n * k)
    y = String[]
    for (i, c) in enumerate(names), j in 1:n
        col = (i - 1) * n + j
        X[:, col] = Float32[3i, -2i, i] .+ 0.3f0 .* randn(rng, Float32, 3)
        push!(y, c)
    end
    return X, y
end

@testset "flux-shapes" begin
    for k in (2, 4)
        X, y = blobs(Xoshiro(k), k)
        m = train_flux(Xoshiro(1), X, y; epochs = 20)
        @test m isa FluxModel
        @test m.classes == sort(unique(y))
        @test size(m(X)) == (k, size(X, 2))
        p = predict_flux(m, X)
        @test p isa Vector{String}
        @test length(p) == size(X, 2)
        @test all(in(m.classes), p)
    end
end

@testset "flux-learns" begin
    for s in SEEDS
        d = load_split(Xoshiro(s), FLOWERS)
        m = train_flux(Xoshiro(100 + s), d.Xtrain, d.ytrain)
        @test acc(predict_flux(m, d.Xtest), d.ytest) >= MIN_ACCURACY
    end
    # Neighbouring blob centres are sqrt(3^2 + 2^2 + 1^2) = 3.7 apart with
    # noise sd 0.3 per coordinate (over 12 sd), so a network that learns at
    # all fits its own training points; 0.95 allows one miss of 36.
    X, y = blobs(Xoshiro(9), 3)
    @test acc(predict_flux(train_flux(Xoshiro(2), X, y), X), y) >= 0.95
end

@testset "flux-seeded" begin
    d = load_split(Xoshiro(1), FLOWERS)
    a = train_flux(Xoshiro(5), d.Xtrain, d.ytrain; epochs = 10)
    b = train_flux(Xoshiro(5), d.Xtrain, d.ytrain; epochs = 10)
    c = train_flux(Xoshiro(6), d.Xtrain, d.ytrain; epochs = 10)
    # Same seed: the same weights, so bit-identical outputs (one thread, CPU).
    @test isequal(a(d.Xtest), b(d.Xtest))
    # Another seed: other initial weights, so other outputs.
    @test !isequal(a(d.Xtest), c(d.Xtest))
end
