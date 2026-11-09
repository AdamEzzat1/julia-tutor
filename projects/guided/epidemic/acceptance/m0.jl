# Acceptance, milestone 0: the package exists and loads. One @testset per behaviour id.
using Epidemic, Test

@testset "package-layout" begin
    @test Epidemic isa Module
    @test nameof(Epidemic) === :Epidemic
end
