# Correct code, and a test that contradicts the spec (whole numbers as Int64).
using Tidy, Test, DataFrames

@testset "reading" begin
    df = read_readings(IOBuffer("site,time,temp,unit,humidity\nn,2026-01-02 03:45,7,C,8\n"))
    @test eltype(df.temp) == Int64
end
