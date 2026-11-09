# Exemplary student tests, milestone 0 (included from a runtests.jl that does `using BayesReg, Test`).
@testset "the package loads" begin
    @test BayesReg isa Module
end
