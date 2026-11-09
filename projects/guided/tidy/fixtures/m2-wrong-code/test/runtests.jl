using Tidy, Test, DataFrames, Dates

row(site, h, t, u, hum) = (site = site, time = DateTime(2026, 1, 1, h), temp = t, unit = u, humidity = hum)
tbl(rs...) = DataFrame(site = String[r.site for r in rs], time = DateTime[r.time for r in rs],
                       temp = Union{Missing,Float64}[r.temp for r in rs], unit = String[r.unit for r in rs],
                       humidity = Union{Missing,Float64}[r.humidity for r in rs])

@testset "clean" begin
    c = clean(tbl(row(" A", 1, 212.0, "F", 50.0), row("a", 2, 10.0, "C", missing)))
    @test c.site == ["a", "a"]
    @test c.temp[1] ≈ 100.0 rtol = 1e-12
    @test c.unit == ["C", "C"]
    @test c.valid == [false, true]     # 100 °C is above the 60 °C bound
end
