# Acceptance, milestone 3: summarize. One @testset per behaviour id.
#
# Means of a few exact binary fractions: every sum here is exact in Float64,
# and one division is correctly rounded, so rtol = 1e-12 is far above the
# rounding error and far below any wrong grouping (which moves a mean by >= 0.25).
using Tidy, Test, DataFrames, Dates

const RTOL = 1e-12

cleaned(rows...) = DataFrame(site = String[r[1] for r in rows],
                             time = DateTime[r[2] for r in rows],
                             temp = Union{Missing,Float64}[r[3] for r in rows],
                             unit = fill("C", length(rows)),
                             humidity = Union{Missing,Float64}[r[4] for r in rows],
                             valid = Bool[r[5] for r in rows])

d(day, h) = DateTime(2026, 3, day, h)

const ROWS = (("north", d(1, 8), 4.0, 80.0, true), ("north", d(1, 12), 9.0, 70.0, true),
              ("north", d(1, 16), 99.0, 70.0, false), ("north", d(2, 8), 3.0, missing, true),
              ("east", d(2, 9), 12.5, missing, true), ("east", d(2, 15), 14.5, missing, true),
              ("east", d(1, 9), 11.0, 60.0, true))

@testset "valid-only" begin
    s = summarize(cleaned(ROWS...))
    r = s[(s.site .== "north") .& (s.date .== Date(2026, 3, 1)), :]
    @test nrow(r) == 1
    @test r.n[1] == 2
    @test isapprox(r.max_temp[1], 9.0; rtol = RTOL)
    @test isapprox(r.mean_temp[1], 6.5; rtol = RTOL)
end

@testset "group-by-day" begin
    s = summarize(cleaned(ROWS...))
    @test names(s) == ["site", "date", "n", "mean_temp", "max_temp", "mean_humidity"]
    @test eltype(s.date) === Date
    @test nrow(s) == 4
    @test sum(s.n) == 6
    r = s[(s.site .== "east") .& (s.date .== Date(2026, 3, 2)), :]
    @test r.n == [2]
    @test isapprox(r.mean_temp[1], 13.5; rtol = RTOL)
end

@testset "humidity-skipmissing" begin
    rows = (("a", d(1, 8), 1.0, 40.0, true), ("a", d(1, 9), 2.0, missing, true), ("a", d(1, 10), 3.0, 50.0, true),
            ("b", d(1, 8), 1.0, missing, true), ("b", d(1, 9), 2.0, missing, true))
    s = summarize(cleaned(rows...))
    @test isapprox(s.mean_humidity[1], 45.0; rtol = RTOL)
    @test ismissing(s.mean_humidity[2])     # a day with no humidity at all
end

@testset "sorted" begin
    s = summarize(cleaned(ROWS...))
    @test s.site == ["east", "east", "north", "north"]
    @test s.date == Date.(2026, 3, [1, 2, 1, 2])
end
