using Classify, Test, Random

const PATH = joinpath(@__DIR__, "..", "data", "flowers.csv")
counts(y) = [count(==(c), y) for c in ["alba", "rosea", "viola"]]

@testset "load_split" begin
    d = load_split(Xoshiro(10), PATH)
    @test d.Xtest isa Matrix{Float32}
    @test size(d.Xtest) == (4, 27)
    @test size(d.Xtrain) == (4, 63)
    @test length(d.ytrain) == 63
    # 40/30/20 per class, 30% each: 12, 9, 6 (exact counts, no tolerance needed)
    for seed in 10:14
        @test counts(load_split(Xoshiro(seed), PATH).ytest) == [12, 9, 6]
    end
    @test counts(load_split(Xoshiro(3), PATH; test_fraction = 0.5).ytest) == [20, 15, 10]
    @test isempty(intersect(Set(eachcol(d.Xtrain)), Set(eachcol(d.Xtest))))
    @test isequal(load_split(Xoshiro(4), PATH), load_split(Xoshiro(4), PATH))
    @test !isequal(load_split(Xoshiro(4), PATH), load_split(Xoshiro(5), PATH))
end
