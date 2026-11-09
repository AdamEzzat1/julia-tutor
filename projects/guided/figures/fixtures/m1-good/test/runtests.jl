using Figures, Test

@testset "loads" begin
    @test Figures isa Module
end

include("prep.jl")
