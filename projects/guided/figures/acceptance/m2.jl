# Acceptance, milestone 2: makie_panel, tested through the returned Figure, never pixels.
# Plotted coordinates are copies of the input (days of the year are integers, the
# temperatures multiples of 0.5), so they are compared exactly (atol = 0, rtol = 0).
using Figures, Test, DataFrames, Dates
using CairoMakie: Figure, Axis, Lines, BarPlot, Legend

const LONG = DataFrame(date = [Date(2025, 1, 30), Date(2025, 1, 31), Date(2025, 2, 2),
                               Date(2025, 1, 30), Date(2025, 2, 1), Date(2025, 2, 2)],
                       city = ["oslo", "oslo", "oslo", "rome", "rome", "rome"],
                       temp = [-2.0, -3.5, -1.0, 10.5, 12.0, 13.5])
const MONTHLY = DataFrame(city = ["oslo", "oslo", "rome", "rome"], month = [1, 2, 1, 2],
                          mean_temp = [-2.75, -1.0, 10.5, 12.75])

cell(b) = (s = b.layoutobservables.gridcontent[].span; (first(s.rows), first(s.cols)))
block_at(fig, T, c) = only(b for b in fig.content if b isa T && cell(b) == c)
xs(pts) = [p[1] for p in pts]
ys(pts) = [p[2] for p in pts]

@testset "makie-structure" begin
    fig = makie_panel(LONG, MONTHLY)
    @test fig isa Figure
    @test count(b -> b isa Axis, fig.content) == 2
    a1 = block_at(fig, Axis, (1, 1))
    @test (a1.title[], a1.xlabel[], a1.ylabel[]) == ("Daily temperature", "Day of year", "Temperature (°C)")
    a2 = block_at(fig, Axis, (1, 2))
    @test (a2.title[], a2.xlabel[], a2.ylabel[]) == ("Monthly mean", "Month", "Mean temperature (°C)")
end

@testset "makie-lines" begin
    fig = makie_panel(LONG, MONTHLY)
    a1 = block_at(fig, Axis, (1, 1))
    lines = [p for p in a1.scene.plots if p isa Lines]
    @test length(lines) == 2
    @test [p.label[] for p in lines] == ["oslo", "rome"]
    @test isapprox(xs(lines[1][1][]), [30, 31, 33]; atol = 0, rtol = 0)     # 2 February is day 33
    @test isapprox(ys(lines[1][1][]), [-2.0, -3.5, -1.0]; atol = 0, rtol = 0)
    @test isapprox(xs(lines[2][1][]), [30, 32, 33]; atol = 0, rtol = 0)
    @test isapprox(ys(lines[2][1][]), [10.5, 12.0, 13.5]; atol = 0, rtol = 0)
end

@testset "makie-bars" begin
    fig = makie_panel(LONG, MONTHLY)
    a2 = block_at(fig, Axis, (1, 2))
    bars = [p for p in a2.scene.plots if p isa BarPlot]
    @test length(bars) == 1
    bp = only(bars)
    @test isapprox(xs(bp[1][]), [1, 2, 1, 2]; atol = 0, rtol = 0)
    @test isapprox(ys(bp[1][]), [-2.75, -1.0, 10.5, 12.75]; atol = 0, rtol = 0)
    @test bp.dodge[] == [1, 1, 2, 2]
end

@testset "makie-legend" begin
    fig = makie_panel(LONG, MONTHLY)
    leg = block_at(fig, Legend, (1, 3))
    groups = leg.entrygroups[]
    @test length(groups) == 1
    @test first(groups[1]) == "City"
    @test [e.label[] for e in last(groups[1])] == ["oslo", "rome"]
end
