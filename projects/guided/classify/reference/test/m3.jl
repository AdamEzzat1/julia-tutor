# Exemplary student tests, milestone 3: MLJ and BetaML.
# FLOWERS comes from m1.jl, hit_rate from m2.jl.
import MLJ

@testset "mlj" begin
    d = load_split(Xoshiro(1), FLOWERS)
    mach = train_mlj(Xoshiro(2), d.Xtrain, d.ytrain)
    steps = [getproperty(mach.model, n) for n in propertynames(mach.model)]
    @test any(s -> s isa MLJ.Standardizer, steps)
    p = predict_mlj(mach, d.Xtest)
    @test p isa Vector{String}
    # Calibrated: the tree's lowest test accuracy over split seeds 1-12 was 0.889.
    @test hit_rate(p, d.ytest) >= 0.85
end

@testset "betaml" begin
    d = load_split(Xoshiro(1), FLOWERS)
    p = predict_betaml(train_betaml(Xoshiro(2), d.Xtrain, d.ytrain), d.Xtest)
    @test p isa Vector{String}
    @test hit_rate(p, d.ytest) >= 0.85    # calibrated as above: lowest seen 0.889
    # Random labels make the forest depend on its random draws, so the same
    # seed must give the same predictions there (forests from seeds 4-7
    # disagreed with seed 3's on 1 to 5 of these 40 points).
    X = randn(Xoshiro(5), Float32, 4, 40)
    y = rand(Xoshiro(6), ["p", "q"], 40)
    Xnew = randn(Xoshiro(7), Float32, 4, 40)
    a = predict_betaml(train_betaml(Xoshiro(3), X, y), Xnew)
    b = predict_betaml(train_betaml(Xoshiro(3), X, y), Xnew)
    @test a == b
end
