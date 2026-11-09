# Acceptance, milestone 0: the package exists and loads. One @testset per behaviour id.
using PyBridge, Test

@testset "package-layout" begin
    @test PyBridge isa Module
    @test nameof(PyBridge) === :PyBridge
end
