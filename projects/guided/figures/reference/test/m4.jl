# Exemplary student tests, milestone 4: Plots.jl, Gadfly and the SVG files.
# Uses PANEL_LONG and PANEL_MONTHLY from m2.jl. Files go to mktempdir().
# Values are copies of the input: atol = 0, rtol = 0.
import Plots, Gadfly

@testset "plots and files" begin
    @testset "Plots.jl series" begin
        p = plots_panel(PANEL_LONG)
        @test [s[:label] for s in p.series_list] == ["lisbon", "vienna"]
        @test isapprox(collect(p.series_list[1][:x]), [31, 34]; atol = 0, rtol = 0)
        @test p[1][:xaxis][:guide] == "Day of year"
        @test p[1][:yaxis][:guide] == "Temperature (°C)"
        @test p[1][:title] == "Daily temperature"
    end
    @testset "Gadfly text" begin
        path = joinpath(mktempdir(), "daily.svg")
        Gadfly.draw(Gadfly.SVG(path, 16Gadfly.cm, 9Gadfly.cm), gadfly_panel(PANEL_LONG))
        svg = read(path, String)
        @test occursin("lisbon", svg) && occursin("vienna", svg)
        @test occursin("Day of year", svg)
    end
    @testset "save_all" begin
        dir = mktempdir()
        paths = save_all(dir, PANEL_LONG, PANEL_MONTHLY)
        @test basename.(paths) == ["aog.svg", "gadfly.svg", "makie.svg", "plots.svg"]
        @test dirname.(paths) == fill(dir, 4)
        @test all(isfile, paths)
        @test all(p -> occursin("<svg", read(p, String)), filter(isfile, paths))
    end
end
