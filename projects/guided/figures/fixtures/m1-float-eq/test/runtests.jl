# Correct code and strong tests, but floats compared with == against literals inside @test (checker JT006).
using Figures, Test, DataFrames, Dates

const T = "date,vienna,lisbon\n2025-01-31,1.5,\n2025-02-01,,11.25\n"

@testset "data preparation" begin
    w = read_wide(IOBuffer(T))
    @test eltype(w.date) == Date
    @test w.vienna[1] == 1.5
    @test ismissing(w.lisbon[1]) && ismissing(w.vienna[2])
    l = long_format(w)
    @test eltype(l.temp) == Float64
    @test l.city == ["lisbon", "vienna"]
    m = monthly_means(DataFrame(date = [Date(2025, 2, 1), Date(2025, 1, 2), Date(2025, 1, 3), Date(2025, 1, 1)],
                                city = ["b", "b", "b", "a"], temp = [2.0, missing, 3.0, 1.0]))
    @test m.city == ["a", "b", "b"]
    @test m.mean_temp[2] == 3.0
end
