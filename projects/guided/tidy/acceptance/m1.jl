# Acceptance, milestone 1: read_readings. One @testset per behaviour id.
using Tidy, Test, DataFrames, Dates, Logging

const TEXT1 = """
site,time,temp,unit,humidity
north,2026-03-01 08:00,4,C,81
north,2026-03-01 12:00,NA,C,70
south,2026-03-01 08:00,59,F,-
east,2026-03-01 16:00,-,C,
east,2026-03-02 09:30,12.5,C,NA
"""

@testset "column-types" begin
    df = read_readings(IOBuffer(TEXT1))
    @test df isa DataFrame
    @test names(df) == ["site", "time", "temp", "unit", "humidity"]
    @test eltype(df.site) === String
    @test eltype(df.unit) === String
    # Whole-number temperatures are still Float64, not Int64.
    @test nonmissingtype(eltype(df.temp)) === Float64
    @test nonmissingtype(eltype(df.humidity)) === Float64
    # A column with no missing value in the file still reads as numbers.
    df2 = read_readings(IOBuffer("site,time,temp,unit,humidity\na,2026-01-01 00:00,1,C,2\n"))
    @test nonmissingtype(eltype(df2.temp)) === Float64
    @test nonmissingtype(eltype(df2.humidity)) === Float64
end

@testset "time-parsed" begin
    df = read_readings(IOBuffer(TEXT1))
    @test eltype(df.time) === DateTime
    @test df.time[1] == DateTime(2026, 3, 1, 8, 0)
    @test df.time[5] == DateTime(2026, 3, 2, 9, 30)
end

@testset "missing-markers" begin
    df = read_readings(IOBuffer(TEXT1))
    @test nrow(df) == 5
    @test ismissing(df.temp[2])        # NA
    @test ismissing(df.temp[4])        # -
    @test ismissing(df.humidity[3])    # -
    @test ismissing(df.humidity[4])    # empty field
    @test ismissing(df.humidity[5])    # NA
    @test count(ismissing, df.temp) == 2
    @test isapprox(df.temp[5], 12.5; rtol = 0)   # parsed exactly: 12.5 is a binary fraction
    # A marker CSV does not know is a parse problem: with a forced column type it
    # becomes missing too, but with a warning. Reading this file must be silent.
    @test_logs min_level = Logging.Warn read_readings(IOBuffer(TEXT1))
end

@testset "path-or-io" begin
    dir = mktempdir()
    path = joinpath(dir, "r.csv")
    write(path, TEXT1)
    a = read_readings(path)
    b = read_readings(IOBuffer(TEXT1))
    @test isequal(a, b)
    @test ismissing(a.temp[4])
end
