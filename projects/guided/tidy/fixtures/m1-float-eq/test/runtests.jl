# Correct code and tests, but a float compared with == inside @test (checker JT006).
using Tidy, Test, DataFrames, Dates, Logging

const T = "site,time,temp,unit,humidity\nn,2026-01-02 03:45,7.5,C,NA\ns,2026-01-02 04:00,-,F,\ne,2026-01-02 05:00,NA,C,-\n"

@testset "reading" begin
    df = read_readings(IOBuffer(T))
    @test df.temp[1] == 7.5
    @test eltype(df.site) == String
    @test df.time[1] == DateTime(2026, 1, 2, 3, 45)
    @test all(ismissing, df.humidity)
    @test ismissing(df.temp[3])
    @test_logs min_level = Logging.Warn read_readings(IOBuffer(T))
    whole = read_readings(IOBuffer("site,time,temp,unit,humidity\nn,2026-01-02 03:45,7,C,8\n"))
    @test nonmissingtype(eltype(whole.temp)) == Float64
    @test nonmissingtype(eltype(whole.humidity)) == Float64
    f = tempname(); write(f, T)
    @test isequal(read_readings(f), df)
end
