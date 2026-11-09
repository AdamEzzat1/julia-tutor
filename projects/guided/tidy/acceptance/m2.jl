# Acceptance, milestone 2: clean. One @testset per behaviour id.
#
# Tolerance for converted temperatures: (t - 32) * 5 / 9 is three correctly
# rounded operations, so any order of them is within a few eps of the exact
# value relative to |t - 32|; rtol = 1e-12 leaves a wide margin and still
# rejects any wrong formula (the nearest wrong one, 9/5, is off by a factor 3.24).
using Tidy, Test, DataFrames, Dates

const RTOL = 1e-12

frame(rows...) = DataFrame(site = String[r[1] for r in rows],
                           time = DateTime[DateTime(2026, 3, 1, r[2]) for r in rows],
                           temp = Union{Missing,Float64}[r[3] for r in rows],
                           unit = String[r[4] for r in rows],
                           humidity = Union{Missing,Float64}[r[5] for r in rows])

@testset "normalize-site" begin
    c = clean(frame((" North", 8, 1.0, "C", 50.0), ("SOUTH ", 9, 2.0, "C", 50.0), ("east", 10, 3.0, "C", 50.0)))
    @test c.site == ["north", "south", "east"]
end

@testset "fahrenheit" begin
    c = clean(frame(("a", 8, 212.0, "F", 50.0), ("a", 9, 50.0, "F", 50.0), ("a", 10, 20.0, "C", 50.0),
                    ("a", 11, missing, "F", 50.0)))
    @test isapprox(c.temp[1], 100.0; rtol = RTOL)
    @test isapprox(c.temp[2], 10.0; rtol = RTOL)
    @test isapprox(c.temp[3], 20.0; rtol = RTOL)     # Celsius rows are left alone
    @test ismissing(c.temp[4])
    @test all(==("C"), c.unit)
end

@testset "duplicates" begin
    # Rows 1 and 2 differ only before cleaning (site spelling): duplicates after it.
    c = clean(frame(("north", 8, 1.0, "C", 50.0), ("North ", 8, 1.0, "C", 50.0), ("north", 9, 2.0, "C", 50.0),
                    ("north", 8, 1.0, "C", 50.0), ("north", 7, 3.0, "C", missing), ("north", 7, 3.0, "C", missing)))
    @test nrow(c) == 3
    @test c.time == [DateTime(2026, 3, 1, h) for h in (8, 9, 7)]   # first kept, order kept
    # A Fahrenheit row equal to a Celsius row once converted is a duplicate too.
    c2 = clean(frame(("a", 8, 50.0, "F", 40.0), ("a", 8, 10.0, "C", 40.0)))
    @test nrow(c2) == 1
end

@testset "range-flag" begin
    c = clean(frame(("a", 1, 60.0, "C", 100.0), ("a", 2, -50.0, "C", 0.0), ("a", 3, 60.5, "C", 50.0),
                    ("a", 4, -50.5, "C", 50.0), ("a", 5, 20.0, "C", 100.5), ("a", 6, 20.0, "C", -0.5),
                    ("a", 7, missing, "C", 50.0), ("a", 8, 20.0, "C", missing), ("a", 9, 140.0, "F", 50.0)))
    @test c.valid isa AbstractVector{Bool}
    @test c.valid == [true, true, false, false, false, false, false, true, true]
    @test nrow(c) == 9     # flagged, not dropped
end

@testset "no-mutation" begin
    df = frame((" North", 8, 212.0, "F", 50.0), (" North", 8, 212.0, "F", 50.0))
    before = deepcopy(df)
    clean(df)
    @test isequal(df, before)
    @test !("valid" in names(df))
end
