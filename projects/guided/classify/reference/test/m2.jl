# Exemplary student tests, milestone 2: train_flux and predict_flux.
# FLOWERS comes from m1.jl, included before this file.

hit_rate(yhat, y) = count(yhat .== y) / length(y)

@testset "flux" begin
    d = load_split(Xoshiro(1), FLOWERS)
    @testset "shapes" begin
        # Two classes, first seen in unsorted order: one output per class, sorted.
        X = Float32[0 0 1 1 5 5 6 6; 0 1 0 1 5 6 5 6]
        y = ["z", "z", "z", "z", "a", "a", "a", "a"]
        m = train_flux(Xoshiro(1), X, y; epochs = 50)
        @test m.classes == ["a", "z"]
        @test size(m(X)) == (2, 8)
        @test predict_flux(m, X) isa Vector{String}
    end
    @testset "learns" begin
        # Calibrated: with training seed 10 + s, the lowest test accuracy over
        # split seeds s = 1-12 was 0.963 (26 of 27); 0.85 allows 4 errors.
        for s in 1:2
            ds = load_split(Xoshiro(s), FLOWERS)
            m = train_flux(Xoshiro(10 + s), ds.Xtrain, ds.ytrain)
            @test hit_rate(predict_flux(m, ds.Xtest), ds.ytest) >= 0.85
        end
    end
    @testset "seeded" begin
        a = train_flux(Xoshiro(3), d.Xtrain, d.ytrain; epochs = 5)
        b = train_flux(Xoshiro(3), d.Xtrain, d.ytrain; epochs = 5)
        @test isequal(a(d.Xtest), b(d.Xtest))   # same seed, same weights: bit-identical
    end
end
