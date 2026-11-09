# Acceptance, milestone 4: compare. One @testset per behaviour id.
using Classify, Test, Random

const FLOWERS = joinpath(@__DIR__, "data", "flowers.csv")
const SEEDS = 1:3

acc(yhat, y) = count(yhat .== y) / length(y)

"""The spec's protocol by hand: split with `rng`, then Flux, MLJ, BetaML with the same `rng`."""
function by_hand(rng)
    d = load_split(rng, FLOWERS)
    f = train_flux(rng, d.Xtrain, d.ytrain)
    af = acc(predict_flux(f, d.Xtest), d.ytest)
    m = train_mlj(rng, d.Xtrain, d.ytrain)
    am = acc(predict_mlj(m, d.Xtest), d.ytest)
    b = train_betaml(rng, d.Xtrain, d.ytrain)
    ab = acc(predict_betaml(b, d.Xtest), d.ytest)
    return Dict("flux" => af, "mlj" => am, "betaml" => ab), length(d.ytrain)
end

@testset "compare-table" begin
    for s in SEEDS
        rows = compare(Xoshiro(s), FLOWERS)
        @test length(rows) == 3
        @test all(r -> propertynames(r) == (:library, :accuracy, :seconds, :size), rows)
        @test sort([r.library for r in rows]) == ["betaml", "flux", "mlj"]
        @test issorted(rows; by = r -> (-r.accuracy, r.library))
        want, ntrain = by_hand(Xoshiro(s))
        for r in rows
            # Both sides are k / 27 from the same predictions: equal up to the
            # last bit; any atol below 1/27 tells two different counts apart.
            @test isapprox(r.accuracy, want[r.library]; atol = 1e-9)
        end
        sz = Dict(r.library => r.size for r in rows)
        @test sz["flux"] == 4 * 16 + 16 + 16 * 3 + 3      # two Dense layers: weights and biases
        @test 3 <= sz["mlj"] <= ntrain                     # at least one leaf per class
        @test sz["betaml"] == 30
    end
end

@testset "compare-timing" begin
    rows = compare(Xoshiro(1), FLOWERS)
    # Calibrated: after a warm-up each fit took 0.0005 to 0.033 s in the
    # container (split seeds 1-3); a first, compiling call took 1.7 s
    # (BetaML) to 9 s (MLJ). The bound of 1 s is 30 times the slowest warm fit.
    @test all(r -> r.seconds isa Float64 && 0 < r.seconds < 1.0, rows)
end
