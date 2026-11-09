# Acceptance, milestone 1: load_split. One @testset per behaviour id.
#
# Everything here is exact: parsing a decimal with one or two digits into
# Float32 is correctly rounded, and a split is a choice of indices, so the
# tests compare labels, counts and whole matrices with `isequal`.
using Classify, Test, Random

const FLOWERS = joinpath(@__DIR__, "data", "flowers.csv")
const SEEDS = 1:8

"""Rows of a file as (measurements, label), parsed the way the spec says."""
function file_rows(path)
    out = Tuple{Vector{Float32},String}[]
    for line in Iterators.drop(eachline(path), 1)
        isempty(strip(line)) && continue
        f = split(strip(line), ',')
        push!(out, (parse.(Float32, f[1:end-1]), String(f[end])))
    end
    return out
end

"""(measurements, label) pairs of one side of a split."""
pairs_of(X, y) = [(X[:, j], y[j]) for j in axes(X, 2)]

# A small file with one rare class: 50 of "a", 10 of "b". A split that ignores
# the classes puts a hypergeometric number of "b" in a 30% test set; over the
# eight seeds below, at least one is more than one sample away from 3.
function unbalanced_file()
    path = joinpath(mktempdir(), "unbalanced.csv")
    open(path, "w") do io
        println(io, "u,v,label")
        for i in 1:60
            println(io, i, ",", 0.5 * i, ",", i <= 50 ? "a" : "b")
        end
    end
    return path
end

@testset "load-columns" begin
    d = load_split(Xoshiro(1), FLOWERS)
    @test keys(d) == (:Xtrain, :ytrain, :Xtest, :ytest)
    @test d.Xtrain isa Matrix{Float32}
    @test d.Xtest isa Matrix{Float32}
    @test d.ytrain isa Vector{String}
    @test d.ytest isa Vector{String}
    @test size(d.Xtrain, 1) == 4
    @test size(d.Xtest, 1) == 4
    @test size(d.Xtrain, 2) == length(d.ytrain)
    @test size(d.Xtest, 2) == length(d.ytest)
    rows = file_rows(FLOWERS)
    got = vcat(pairs_of(d.Xtrain, d.ytrain), pairs_of(d.Xtest, d.ytest))
    # Every sample, with its own label, exactly once.
    @test isequal(sort(got), sort(rows))
end

@testset "stratified-split" begin
    rows = file_rows(FLOWERS)
    for s in SEEDS, f in (0.3, 0.5)
        d = load_split(Xoshiro(s), FLOWERS; test_fraction = f)
        @test length(d.ytrain) + length(d.ytest) == length(rows)
        for c in unique(last.(rows))
            n = count(r -> r[2] == c, rows)
            @test abs(count(==(c), d.ytest) - f * n) <= 1
        end
        # No sample on both sides (the file has no duplicate rows).
        @test isempty(intersect(Set(pairs_of(d.Xtrain, d.ytrain)), Set(pairs_of(d.Xtest, d.ytest))))
    end
    path = unbalanced_file()
    for s in SEEDS
        d = load_split(Xoshiro(s), path)
        @test abs(count(==("b"), d.ytest) - 3) <= 1
        @test abs(count(==("a"), d.ytest) - 15) <= 1
        @test length(d.ytrain) + length(d.ytest) == 60
    end
end

@testset "rng-reproducible" begin
    a = load_split(Xoshiro(3), FLOWERS)
    b = load_split(Xoshiro(3), FLOWERS)
    @test isequal(a, b)
    # Different seeds: some pair of the eight differs (each split is one of
    # astronomically many, so equal splits for all would mean the seed is ignored).
    splits = [load_split(Xoshiro(s), FLOWERS).Xtest for s in SEEDS]
    @test length(unique(splits)) > 1
    @test !isequal(load_split(Xoshiro(1), FLOWERS), load_split(Xoshiro(2), FLOWERS))
end
