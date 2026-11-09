# Exemplary student tests, milestone 0 (included from a runtests.jl that does `using PyBridge, Test`).
@testset "the package loads" begin
    @test PyBridge isa Module
end
