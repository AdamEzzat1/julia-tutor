# Acceptance, milestone 0: the package exists and loads. One @testset per behaviour id.
using DerivCheck, Test

@testset "package-layout" begin
    @test DerivCheck isa Module
    @test nameof(DerivCheck) === :DerivCheck
end
