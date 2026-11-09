# Acceptance, milestone 0: the package exists and loads. One @testset per behaviour id.
using Tidy, Test

@testset "package-layout" begin
    @test Tidy isa Module
    @test nameof(Tidy) === :Tidy
end
