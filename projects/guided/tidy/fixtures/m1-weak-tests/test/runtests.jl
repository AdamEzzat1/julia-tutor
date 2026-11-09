# Correct code, tests that only check the shape of the result.
using Tidy, Test, DataFrames

@testset "reading" begin
    df = read_readings(IOBuffer("site,time,temp,unit,humidity\nn,2026-01-02 03:45,7,C,NA\ns,2026-01-02 04:00,-,F,\n"))
    @test nrow(df) == 2
    @test names(df) == ["site", "time", "temp", "unit", "humidity"]
end
