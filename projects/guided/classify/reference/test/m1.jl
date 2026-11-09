# Exemplary student tests, milestone 1: load_split.
# A split only chooses indices and parsing one-decimal numbers into Float32
# is correctly rounded, so these tests compare counts, labels and whole
# matrices exactly (isequal), with no tolerance needed.
using Random

const FLOWERS = joinpath(@__DIR__, "..", "data", "flowers.csv")

@testset "load_split" begin
    d = load_split(Xoshiro(1), FLOWERS)
    @testset "columns" begin
        @test eltype(d.Xtrain) == Float32
        @test size(d.Xtrain, 1) == 4                # one row per measurement
        @test size(d.Xtrain, 2) == length(d.ytrain)  # one column per sample
        @test size(d.Xtest, 2) == length(d.ytest)
        @test length(d.ytrain) + length(d.ytest) == 90
    end
    @testset "stratified" begin
        # 40 alba, 30 rosea, 20 viola in the file: 30% is 12, 9 and 6.
        for s in 1:5
            t = load_split(Xoshiro(s), FLOWERS).ytest
            @test [count(==(c), t) for c in ["alba", "rosea", "viola"]] == [12, 9, 6]
        end
        h = load_split(Xoshiro(2), FLOWERS; test_fraction = 0.5).ytest
        @test [count(==(c), h) for c in ["alba", "rosea", "viola"]] == [20, 15, 10]
        # No column is on both sides (the file has no repeated rows).
        cols(X) = Set(eachcol(X))
        @test isempty(intersect(cols(d.Xtrain), cols(d.Xtest)))
    end
    @testset "seeded" begin
        @test isequal(load_split(Xoshiro(7), FLOWERS), load_split(Xoshiro(7), FLOWERS))
        @test !isequal(load_split(Xoshiro(7), FLOWERS), load_split(Xoshiro(8), FLOWERS))
    end
end
