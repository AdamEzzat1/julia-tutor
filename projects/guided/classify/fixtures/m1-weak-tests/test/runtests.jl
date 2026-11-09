# Correct code, tests that only check that the pieces add up.
using Classify, Test, Random

@testset "load_split" begin
    d = load_split(Xoshiro(1), joinpath(@__DIR__, "..", "data", "flowers.csv"))
    @test size(d.Xtrain, 2) == length(d.ytrain)
    @test size(d.Xtest, 2) == length(d.ytest)
end
