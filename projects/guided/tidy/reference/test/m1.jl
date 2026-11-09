# Exemplary student tests, milestone 1: what a careful student writes for read_readings.
using DataFrames, Dates, Logging

const SAMPLE = """
site,time,temp,unit,humidity
north,2026-03-01 08:00,4,C,81
north,2026-03-01 12:00,NA,C,NA
south,2026-03-01 08:00,59,F,-
east,2026-03-02 16:30,-,C,
"""

@testset "read_readings" begin
    df = read_readings(IOBuffer(SAMPLE))
    @testset "types" begin
        @test eltype(df.site) == String
        @test nonmissingtype(eltype(df.temp)) == Float64     # "4" and "59" are whole numbers
        @test nonmissingtype(eltype(df.humidity)) == Float64
        whole = read_readings(IOBuffer("site,time,temp,unit,humidity\na,2026-01-01 00:00,1,C,2\n"))
        @test nonmissingtype(eltype(whole.temp)) == Float64
        @test nonmissingtype(eltype(whole.humidity)) == Float64
    end
    @testset "times" begin
        @test df.time[4] == DateTime(2026, 3, 2, 16, 30)
        @test eltype(df.time) == DateTime
    end
    @testset "missing markers" begin
        @test ismissing(df.temp[2])         # NA
        @test ismissing(df.temp[4])         # -
        @test ismissing(df.humidity[2])     # NA
        @test ismissing(df.humidity[3])     # -
        @test ismissing(df.humidity[4])     # empty
        @test_logs min_level = Logging.Warn read_readings(IOBuffer(SAMPLE))   # no parse warnings
    end
    @testset "from a file" begin
        path = joinpath(mktempdir(), "sample.csv")
        write(path, SAMPLE)
        @test isequal(read_readings(path), df)
    end
end
