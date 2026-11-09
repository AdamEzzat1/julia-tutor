# Acceptance, milestone 0: the package exists and loads. One @testset per behaviour id.
using Production, Test

@testset "package-layout" begin
    @test Production isa Module
    @test nameof(Production) === :Production
end
