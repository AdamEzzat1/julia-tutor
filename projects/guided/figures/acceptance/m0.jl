# Acceptance, milestone 0: the package exists and loads. One @testset per behaviour id.
using Figures, Test

@testset "package-layout" begin
    @test Figures isa Module
    @test nameof(Figures) === :Figures
end
