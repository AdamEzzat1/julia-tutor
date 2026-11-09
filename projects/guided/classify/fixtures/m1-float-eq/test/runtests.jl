# Correct code; the share of the test set is compared with `==` against a float literal.
using Classify, Test, Random

@testset "load_split" begin
    d = load_split(Xoshiro(1), joinpath(@__DIR__, "..", "data", "flowers.csv"))
    @test length(d.ytest) / 90 == 0.3
end
