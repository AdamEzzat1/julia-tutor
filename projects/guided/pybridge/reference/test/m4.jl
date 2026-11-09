# Exemplary student tests, milestone 4: what crossing costs.
@testset "boundary costs" begin
    n = 10^6
    b = boundary_bytes(n)
    @test b.view < 10 * 1024             # a Python object, not n values
    @test boundary_bytes(10).view < 10 * 1024
    @test b.copy >= 8n                   # 8 bytes per Float64
end
