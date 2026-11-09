using Classify, Test, Random

const PATH = joinpath(@__DIR__, "..", "data", "flowers.csv")

@testset "split" begin
    d = load_split(Xoshiro(1), PATH)
    @test size(d.Xtest) == (4, 27)
    @test [count(==(c), d.ytest) for c in ["alba", "rosea", "viola"]] == [12, 9, 6]
end

@testset "flux" begin
    d = load_split(Xoshiro(1), PATH)
    m = train_flux(Xoshiro(2), d.Xtrain, d.ytrain; epochs = 5)
    @test m.classes == ["alba", "rosea", "viola"]
    @test size(m(d.Xtest)) == (3, 27)
end
