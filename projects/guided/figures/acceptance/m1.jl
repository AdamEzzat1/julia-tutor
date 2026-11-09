# Acceptance, milestone 1: read_wide, long_format, monthly_means. One @testset per behaviour id.
# Every value below is a multiple of 0.5, so parsing it and copying it are exact:
# those comparisons use isequal on purpose. Means get a derived rtol.
using Figures, Test, DataFrames, Dates

const WIDE_TEXT = """
date,rome,oslo,bergen
2025-01-30,10.5,-2.0,1.5
2025-01-31,,-3.5,2.0
2025-02-01,12,,2.5
2025-02-02,13.5,-1.0,
"""

@testset "read-wide" begin
    df = read_wide(IOBuffer(WIDE_TEXT))
    @test df isa DataFrame
    @test names(df) == ["date", "rome", "oslo", "bergen"]
    @test eltype(df.date) === Date
    @test df.date == [Date(2025, 1, 30), Date(2025, 1, 31), Date(2025, 2, 1), Date(2025, 2, 2)]
    for c in ["rome", "oslo", "bergen"]
        @test nonmissingtype(eltype(df[!, c])) === Float64
    end
    # An empty field is missing, wherever it is on the line (middle or end), never 0.
    @test isequal(collect(df.rome), [10.5, missing, 12.0, 13.5])
    @test isequal(collect(df.oslo), [-2.0, -3.5, missing, -1.0])
    @test isequal(collect(df.bergen), [1.5, 2.0, 2.5, missing])
end

@testset "long-format" begin
    wide = DataFrame(date = [Date(2025, 1, 30), Date(2025, 1, 31), Date(2025, 2, 1)],
                     rome = [10.5, missing, 12.0], oslo = [-2.0, -3.5, missing])
    long = long_format(wide)
    @test names(long) == ["date", "city", "temp"]
    @test eltype(long.city) === String
    @test eltype(long.temp) === Float64
    @test nrow(long) == 4                       # 6 cells, 2 of them missing
    @test long.city == ["oslo", "oslo", "rome", "rome"]
    @test long.date == [Date(2025, 1, 30), Date(2025, 1, 31), Date(2025, 1, 30), Date(2025, 2, 1)]
    @test isequal(long.temp, [-2.0, -3.5, 10.5, 12.0])   # copies of the input: exact
    @test nrow(wide) == 3 && ismissing(wide.rome[2])     # the input is unchanged
end

@testset "monthly-means" begin
    long = DataFrame(date = [Date(2025, 2, 3), Date(2025, 1, 5), Date(2025, 1, 9), Date(2025, 1, 7), Date(2025, 2, 1)],
                     city = ["rome", "rome", "oslo", "oslo", "rome"],
                     temp = Union{Missing, Float64}[12.0, 9.0, -2.0, missing, 14.5])
    m = monthly_means(long)
    @test names(m) == ["city", "month", "mean_temp"]
    @test m.city == ["oslo", "rome", "rome"]
    @test m.month == [1, 1, 2]
    @test eltype(m.month) <: Integer
    @test nonmissingtype(eltype(m.mean_temp)) === Float64
    # Means of at most 2 values: one rounding in the sum, one in the division, so the
    # error is below 2 eps relative (here even 0); rtol = 1e-12 is far above that.
    @test isapprox(m.mean_temp, [-2.0, 9.0, 13.25]; rtol = 1e-12)
end
