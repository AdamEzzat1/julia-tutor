# Exemplary student tests, milestone 0 (included from a runtests.jl that does `using DerivCheck, Test`).
@testset "the package loads" begin
    @test DerivCheck isa Module
end
