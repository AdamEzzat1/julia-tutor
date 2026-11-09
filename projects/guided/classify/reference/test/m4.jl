# Exemplary student tests, milestone 4: compare.
# FLOWERS comes from m1.jl, hit_rate from m2.jl.

@testset "compare" begin
    rows = compare(Xoshiro(1), FLOWERS)
    @test sort([r.library for r in rows]) == ["betaml", "flux", "mlj"]
    @test issorted(rows; by = r -> (-r.accuracy, r.library))
    # The same protocol by hand: the split, then Flux, MLJ, BetaML on one rng.
    rng = Xoshiro(1)
    d = load_split(rng, FLOWERS)
    f = hit_rate(predict_flux(train_flux(rng, d.Xtrain, d.ytrain), d.Xtest), d.ytest)
    m = hit_rate(predict_mlj(train_mlj(rng, d.Xtrain, d.ytrain), d.Xtest), d.ytest)
    b = hit_rate(predict_betaml(train_betaml(rng, d.Xtrain, d.ytrain), d.Xtest), d.ytest)
    got = Dict(r.library => r.accuracy for r in rows)
    # Both are k/27 from the same predictions; atol well below 1/27.
    @test isapprox(got["flux"], f; atol = 1e-9)
    @test isapprox(got["mlj"], m; atol = 1e-9)
    @test isapprox(got["betaml"], b; atol = 1e-9)
    @test all(r -> r.seconds > 0, rows)
end
