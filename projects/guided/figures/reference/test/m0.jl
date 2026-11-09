# Exemplary student tests, milestone 0 (included from a runtests.jl that does `using Figures, Test`).
@testset "the package loads" begin
    @test Figures isa Module
end
