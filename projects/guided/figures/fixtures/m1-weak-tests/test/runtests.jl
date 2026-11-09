# Correct code, tests that only check the shape of the results.
using Figures, Test, DataFrames, Dates

@testset "data preparation" begin
    w = read_wide(IOBuffer("date,a,b\n2025-01-01,1.5,2.5\n2025-01-02,3.5,4.5\n"))
    @test names(w) == ["date", "a", "b"]
    @test nrow(w) == 2
    l = long_format(w)
    @test names(l) == ["date", "city", "temp"]
    @test nrow(l) == 4
    m = monthly_means(l)
    @test names(m) == ["city", "month", "mean_temp"]
end
