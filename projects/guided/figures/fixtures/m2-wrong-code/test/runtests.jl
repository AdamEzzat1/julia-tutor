# Wrong code (x is the day of the month), with the exemplary tests up to milestone 2.
using Figures, Test

@testset "the package loads" begin
    @test Figures isa Module
end
# The temperatures are multiples of 0.25, so parsing and copying them is exact
# (isequal); means use an rtol derived below.
using DataFrames, Dates

const SAMPLE = """
date,vienna,lisbon
2025-01-31,1.5,
2025-02-01,,11.25
2025-02-02,-0.5,12
"""

@testset "data preparation" begin
    @testset "read_wide" begin
        w = read_wide(IOBuffer(SAMPLE))
        @test names(w) == ["date", "vienna", "lisbon"]
        @test eltype(w.date) == Date
        @test w.date[2] == Date(2025, 2, 1)
        @test nonmissingtype(eltype(w.lisbon)) == Float64
        @test ismissing(w.lisbon[1])       # empty at the end of the line
        @test ismissing(w.vienna[2])       # empty in the middle
        @test isequal(collect(w.lisbon), [missing, 11.25, 12.0])
    end
    @testset "long_format" begin
        wide = DataFrame(date = [Date(2025, 1, 31), Date(2025, 2, 1)],
                         vienna = [1.5, missing], lisbon = [10.0, 11.25])
        l = long_format(wide)
        @test names(l) == ["date", "city", "temp"]
        @test eltype(l.temp) == Float64
        @test nrow(l) == 3
        @test l.city == ["lisbon", "lisbon", "vienna"]
        @test l.date == [Date(2025, 1, 31), Date(2025, 2, 1), Date(2025, 1, 31)]
        @test isequal(l.temp, [10.0, 11.25, 1.5])
    end
    @testset "monthly_means" begin
        long = DataFrame(date = [Date(2025, 2, 1), Date(2025, 1, 31), Date(2025, 1, 30), Date(2025, 1, 29)],
                         city = ["vienna", "vienna", "lisbon", "vienna"],
                         temp = [2.0, missing, 10.0, 1.0])
        m = monthly_means(long)
        @test m.city == ["lisbon", "vienna", "vienna"]
        @test m.month == [1, 1, 2]
        # A mean of one or two values: at most two roundings, relative error < 2 eps.
        @test m.mean_temp ≈ [10.0, 1.0, 2.0] rtol = 1e-12
    end
end
# Plotted values are copies of the input (integer days, temperatures that are
# multiples of 0.5), so they are compared exactly: atol = 0, rtol = 0.
using DataFrames, Dates
using CairoMakie: Axis, Lines, BarPlot, Legend

# Two cities; vienna comes first in the input, but lisbon sorts first.
const PANEL_LONG = DataFrame(date = [Date(2025, 1, 31), Date(2025, 2, 1), Date(2025, 1, 31), Date(2025, 2, 3)],
                             city = ["vienna", "vienna", "lisbon", "lisbon"],
                             temp = [1.5, 2.0, 10.0, 11.5])
const PANEL_MONTHLY = DataFrame(city = ["lisbon", "lisbon", "vienna", "vienna"], month = [1, 2, 1, 2],
                                mean_temp = [10.0, 11.5, 1.5, 2.0])

gridcell(b) = (s = b.layoutobservables.gridcontent[].span; (first(s.rows), first(s.cols)))

@testset "makie panel" begin
    fig = makie_panel(PANEL_LONG, PANEL_MONTHLY)
    axs = sort([b for b in fig.content if b isa Axis]; by = gridcell)
    @test length(axs) == 2
    daily, monthly = axs
    @testset "axes" begin
        @test gridcell(daily) == (1, 1)
        @test daily.title[] == "Daily temperature"
        @test daily.xlabel[] == "Day of year"
        @test daily.ylabel[] == "Temperature (°C)"
        @test gridcell(monthly) == (1, 2)
        @test monthly.title[] == "Monthly mean"
        @test monthly.xlabel[] == "Month"
        @test monthly.ylabel[] == "Mean temperature (°C)"
    end
    @testset "lines" begin
        ls = filter(p -> p isa Lines, daily.scene.plots)
        @test [p.label[] for p in ls] == ["lisbon", "vienna"]
        # 31 January is day 31, 3 February day 34: a day-of-month x would give 3.
        @test isapprox([q[1] for q in ls[1][1][]], [31, 34]; atol = 0, rtol = 0)
        @test isapprox([q[2] for q in ls[2][1][]], [1.5, 2.0]; atol = 0, rtol = 0)
    end
    @testset "bars" begin
        bp = only(filter(p -> p isa BarPlot, monthly.scene.plots))
        @test isapprox([q[2] for q in bp[1][]], PANEL_MONTHLY.mean_temp; atol = 0, rtol = 0)
        @test bp.dodge[] == [1, 1, 2, 2]
    end
    @testset "legend" begin
        leg = only(b for b in fig.content if b isa Legend)
        @test gridcell(leg) == (1, 3)
        (title, entries) = only(leg.entrygroups[])
        @test title == "City"
        @test [e.label[] for e in entries] == ["lisbon", "vienna"]
    end
end
