# Acceptance, milestone 0: the package exists and loads. One @testset per behaviour id.
using Classify, Test

@testset "package-layout" begin
    @test Classify isa Module
    @test nameof(Classify) === :Classify
end
