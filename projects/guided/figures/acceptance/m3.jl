# Acceptance, milestone 3: aog_panel, tested through the returned Figure.
# draw!(fig[1, k], ...) puts each axis in a nested grid, so axes are found by what
# they hold or by their title, not by cell. Coordinates are copies of the input
# (integers and multiples of 0.5): compared exactly (atol = 0, rtol = 0).
using Figures, Test, DataFrames, Dates
using CairoMakie: Figure, Axis, Lines, BarPlot, Legend

const LONG = DataFrame(date = [Date(2025, 1, 30), Date(2025, 1, 31), Date(2025, 2, 2),
                               Date(2025, 1, 30), Date(2025, 2, 1), Date(2025, 2, 2)],
                       city = ["oslo", "oslo", "oslo", "rome", "rome", "rome"],
                       temp = [-2.0, -3.5, -1.0, 10.5, 12.0, 13.5])
const MONTHLY = DataFrame(city = ["oslo", "oslo", "rome", "rome"], month = [1, 2, 1, 2],
                          mean_temp = [-2.75, -1.0, 10.5, 12.75])

cell(b) = (s = b.layoutobservables.gridcontent[].span; (first(s.rows), first(s.cols)))
axes_of(fig) = [b for b in fig.content if b isa Axis]
holding(fig, T) = only(a for a in axes_of(fig) if any(p -> p isa T, a.scene.plots))
titled(fig, t) = only(a for a in axes_of(fig) if a.title[] == t)
xs(pts) = [p[1] for p in pts]
ys(pts) = [p[2] for p in pts]

@testset "aog-mapping" begin
    fig = aog_panel(LONG, MONTHLY)
    @test fig isa Figure
    lines = [p for p in holding(fig, Lines).scene.plots if p isa Lines]
    @test length(lines) == 2
    @test allunique([p.color[] for p in lines])
    @test isapprox(xs(lines[1][1][]), [30, 31, 33]; atol = 0, rtol = 0)     # oslo, days of the year
    @test isapprox(ys(lines[1][1][]), [-2.0, -3.5, -1.0]; atol = 0, rtol = 0)
    @test isapprox(xs(lines[2][1][]), [30, 32, 33]; atol = 0, rtol = 0)     # rome
    bars = [p for p in holding(fig, BarPlot).scene.plots if p isa BarPlot]
    pts = sort([(q[1], q[2]) for b in bars for q in b[1][]])
    @test length(pts) == 4
    @test isapprox(ys(pts), [-2.75, 10.5, -1.0, 12.75]; atol = 0, rtol = 0)   # sorted by (month, mean)
end

@testset "aog-labels" begin
    fig = aog_panel(LONG, MONTHLY)
    @test length(axes_of(fig)) == 2
    a1 = titled(fig, "Daily temperature")
    @test (a1.xlabel[], a1.ylabel[]) == ("Day of year", "Temperature (°C)")
    a2 = titled(fig, "Monthly mean")
    @test (a2.xlabel[], a2.ylabel[]) == ("Month", "Mean temperature (°C)")
end

@testset "aog-legend" begin
    fig = aog_panel(LONG, MONTHLY)
    leg = only(b for b in fig.content if b isa Legend)
    @test cell(leg) == (1, 3)
    groups = leg.entrygroups[]
    @test length(groups) == 1
    @test first(groups[1]) == "City"
    @test [e.label[] for e in last(groups[1])] == ["oslo", "rome"]
end
