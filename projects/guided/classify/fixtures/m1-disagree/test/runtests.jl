# Correct code, and a test that contradicts the spec (it expects Float64, the spec says Float32).
using Classify, Test, Random

@testset "load_split" begin
    d = load_split(Xoshiro(1), joinpath(@__DIR__, "..", "data", "flowers.csv"))
    @test eltype(d.Xtrain) == Float64
end
