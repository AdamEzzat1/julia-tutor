# Exemplary student tests, milestone 1: what a careful student writes for the data preparation.
# The temperatures are multiples of 0.25, so parsing and copying them is exact
# (isequal); means use an rtol derived below.
using DataFrames, Dates

const SAMPLE = """
date,vienna,lisbon
2025-01-31,1.5,
2025-02-01,,11.25
2025-02-02,-0.5,12
"""

@testset "data preparation" begin
    @testset "read_wide" begin
        w = read_wide(IOBuffer(SAMPLE))
        @test names(w) == ["date", "vienna", "lisbon"]
        @test eltype(w.date) == Date
        @test w.date[2] == Date(2025, 2, 1)
        @test nonmissingtype(eltype(w.lisbon)) == Float64
        @test ismissing(w.lisbon[1])       # empty at the end of the line
        @test ismissing(w.vienna[2])       # empty in the middle
        @test isequal(collect(w.lisbon), [missing, 11.25, 12.0])
    end
    @testset "long_format" begin
        wide = DataFrame(date = [Date(2025, 1, 31), Date(2025, 2, 1)],
                         vienna = [1.5, missing], lisbon = [10.0, 11.25])
        l = long_format(wide)
        @test names(l) == ["date", "city", "temp"]
        @test eltype(l.temp) == Float64
        @test nrow(l) == 3
        @test l.city == ["lisbon", "lisbon", "vienna"]
        @test l.date == [Date(2025, 1, 31), Date(2025, 2, 1), Date(2025, 1, 31)]
        @test isequal(l.temp, [10.0, 11.25, 1.5])
    end
    @testset "monthly_means" begin
        long = DataFrame(date = [Date(2025, 2, 1), Date(2025, 1, 31), Date(2025, 1, 30), Date(2025, 1, 29)],
                         city = ["vienna", "vienna", "lisbon", "vienna"],
                         temp = [2.0, missing, 10.0, 1.0])
        m = monthly_means(long)
        @test m.city == ["lisbon", "vienna", "vienna"]
        @test m.month == [1, 1, 2]
        # A mean of one or two values: at most two roundings, relative error < 2 eps.
        @test m.mean_temp ≈ [10.0, 1.0, 2.0] rtol = 1e-12
    end
end
