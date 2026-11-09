# Acceptance, milestone 4: what each conversion allocates. One @testset per behaviour id.
#
# Bounds: a view is one Python object and its wrapper (measured: 744 bytes on
# the second call at n = 10^6), so 10 KiB leaves room for other platforms and
# stays far below a copy's 8 MB. A copy holds 8n bytes of data plus a constant
# (measured: 8,001,352 bytes at n = 10^6); doubling n must add 8n bytes, within
# 1% for the constant and the allocator's rounding.
using PyBridge, Test

@testset "view-cost" begin
    @test boundary_bytes(10).view < 10 * 1024
    @test boundary_bytes(10^6).view < 10 * 1024
end

@testset "copy-cost" begin
    n = 10^6
    c1 = boundary_bytes(n).copy
    c2 = boundary_bytes(2n).copy
    @test c1 >= 8n
    @test abs((c2 - c1) - 8n) <= 0.01 * 8n
end
