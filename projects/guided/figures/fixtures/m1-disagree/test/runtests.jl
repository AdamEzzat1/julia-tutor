# Correct code; the tests expect the long table sorted by date first, which the spec does not say.
using Figures, Test, DataFrames, Dates

@testset "long format" begin
    wide = DataFrame(date = [Date(2025, 1, 1), Date(2025, 1, 2)], b = [1.5, 2.5], a = [3.5, 4.5])
    l = long_format(wide)
    @test l.city == ["a", "b", "a", "b"]
end
