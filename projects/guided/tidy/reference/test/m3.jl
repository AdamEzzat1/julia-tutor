# Exemplary student tests, milestone 3: summarize.
using DataFrames, Dates

# Means of exact binary fractions: one rounded division, so rtol = 1e-12 is generous.
const MTOL = 1e-12

ctable(rows) = DataFrame(site = String[r[1] for r in rows], time = DateTime[r[2] for r in rows],
                         temp = Union{Missing,Float64}[r[3] for r in rows], unit = fill("C", length(rows)),
                         humidity = Union{Missing,Float64}[r[4] for r in rows], valid = Bool[r[5] for r in rows])

@testset "summarize" begin
    t(day, h) = DateTime(2026, 3, day, h)
    s = summarize(ctable([("b", t(1, 1), 2.0, 10.0, true), ("b", t(1, 2), 4.0, missing, true),
                          ("b", t(1, 3), 50.0, 10.0, false), ("b", t(2, 1), 1.0, missing, true),
                          ("a", t(1, 1), 3.0, 20.0, true)]))
    @test nrow(s) == 3
    @test s.site == ["a", "b", "b"]
    @test s.date == [Date(2026, 3, 1), Date(2026, 3, 1), Date(2026, 3, 2)]
    @test s.n == [1, 2, 1]
    @test s.mean_temp[2] ≈ 3.0 rtol = MTOL
    @test s.max_temp[2] ≈ 4.0 rtol = MTOL
    @test s.mean_humidity[2] ≈ 10.0 rtol = MTOL
    @test ismissing(s.mean_humidity[3])
end
