# Acceptance, milestone 0: the package exists and loads. One @testset per behaviour id.
using BayesReg, Test

@testset "package-layout" begin
    @test BayesReg isa Module
    @test nameof(BayesReg) === :BayesReg
end
