# Exemplary student tests, milestone 2: clean.
using DataFrames, Dates

# Celsius from Fahrenheit is three rounded operations: rtol = 1e-12 is far
# above their error and far below any wrong formula.
const CTOL = 1e-12

mk(site, hour, temp, unit, hum) = (site = site, time = DateTime(2026, 3, 1, hour), temp = temp, unit = unit, humidity = hum)
table(rows) = DataFrame(site = String[r.site for r in rows], time = DateTime[r.time for r in rows],
                        temp = Union{Missing,Float64}[r.temp for r in rows], unit = String[r.unit for r in rows],
                        humidity = Union{Missing,Float64}[r.humidity for r in rows])

@testset "clean" begin
    @testset "site names" begin
        c = clean(table([mk(" North ", 1, 1.0, "C", 1.0), mk("south", 2, 1.0, "C", 1.0)]))
        @test c.site == ["north", "south"]
    end
    @testset "fahrenheit" begin
        c = clean(table([mk("a", 1, 212.0, "F", 1.0), mk("a", 2, 30.0, "C", 1.0)]))
        @test c.temp[1] ≈ 100.0 rtol = CTOL
        @test c.temp[2] ≈ 30.0 rtol = CTOL
        @test c.unit == ["C", "C"]
    end
    @testset "duplicates" begin
        c = clean(table([mk("a", 1, 1.0, "C", 1.0), mk("a", 1, 1.0, "C", 1.0), mk("A ", 1, 1.0, "C", 1.0),
                         mk("a", 2, 1.0, "C", 1.0)]))
        @test nrow(c) == 2
        @test c.time == [DateTime(2026, 3, 1, 1), DateTime(2026, 3, 1, 2)]
    end
    @testset "valid flag" begin
        c = clean(table([mk("a", 1, 60.0, "C", 100.0), mk("a", 2, 61.0, "C", 50.0), mk("a", 3, 20.0, "C", missing),
                         mk("a", 4, missing, "C", 50.0), mk("a", 5, 20.0, "C", 101.0), mk("a", 6, -50.0, "C", 0.0)]))
        @test c.valid == [true, false, true, false, false, true]
    end
    @testset "input unchanged" begin
        df = table([mk(" A", 1, 50.0, "F", 1.0), mk(" A", 1, 50.0, "F", 1.0)])
        copy_before = copy(df)
        clean(df)
        @test isequal(df, copy_before)
    end
end
