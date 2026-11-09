# Exemplary student tests, milestone 0 (included from a runtests.jl that does `using Epidemic, Test`).
@testset "the package loads" begin
    @test Epidemic isa Module
end
