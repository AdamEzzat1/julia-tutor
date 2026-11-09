# Exemplary student tests, milestone 0 (included from a runtests.jl that does `using Production, Test`).
@testset "the package loads" begin
    @test Production isa Module
end
