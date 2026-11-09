# Acceptance, milestone 4: plots_panel, gadfly_panel, save_all. Structure and SVG text,
# never bytes. Files go to mktempdir() (the container's root is read-only).
# Coordinates are copies of the input (integers, multiples of 0.5): atol = 0.
using Figures, Test, DataFrames, Dates
import Plots, Gadfly

const LONG = DataFrame(date = [Date(2025, 1, 30), Date(2025, 1, 31), Date(2025, 2, 2),
                               Date(2025, 1, 30), Date(2025, 2, 1), Date(2025, 2, 2)],
                       city = ["oslo", "oslo", "oslo", "rome", "rome", "rome"],
                       temp = [-2.0, -3.5, -1.0, 10.5, 12.0, 13.5])
const MONTHLY = DataFrame(city = ["oslo", "oslo", "rome", "rome"], month = [1, 2, 1, 2],
                          mean_temp = [-2.75, -1.0, 10.5, 12.75])

@testset "plots-series" begin
    p = plots_panel(LONG)
    @test p isa Plots.Plot
    @test length(p.series_list) == 2
    @test [s[:label] for s in p.series_list] == ["oslo", "rome"]
    @test isapprox(collect(p.series_list[1][:x]), [30, 31, 33]; atol = 0, rtol = 0)
    @test isapprox(collect(p.series_list[2][:y]), [10.5, 12.0, 13.5]; atol = 0, rtol = 0)
    @test p[1][:title] == "Daily temperature"
    @test p[1][:xaxis][:guide] == "Day of year"
    @test p[1][:yaxis][:guide] == "Temperature (°C)"
end

@testset "gadfly-svg" begin
    p = gadfly_panel(LONG)
    @test p isa Gadfly.Plot
    path = joinpath(mktempdir(), "g.svg")
    Gadfly.draw(Gadfly.SVG(path, 16Gadfly.cm, 9Gadfly.cm), p)
    s = read(path, String)
    for t in ["oslo", "rome", "City", "Daily temperature", "Day of year", "Temperature"]
        @test occursin(t, s)
    end
end

@testset "svg-files" begin
    dir = mktempdir()
    paths = save_all(dir, LONG, MONTHLY)
    @test paths == [joinpath(dir, n) for n in ["aog.svg", "gadfly.svg", "makie.svg", "plots.svg"]]
    @test all(isfile, paths)
    for p in paths
        isfile(p) && @test occursin("<svg", read(p, String))
    end
    g = joinpath(dir, "gadfly.svg")
    @test isfile(g) && occursin("oslo", read(g, String)) && occursin("rome", read(g, String))
    @test isfile(joinpath(dir, "plots.svg"))
end
