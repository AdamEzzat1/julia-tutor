# Exemplary student tests, milestone 3: the AlgebraOfGraphics figure.
# Uses PANEL_LONG and PANEL_MONTHLY from m2.jl. draw! nests each axis in a grid of
# its own, so axes are looked up by title. Values are copies: atol = 0, rtol = 0.
using CairoMakie: Axis, Lines, Legend

@testset "aog panel" begin
    fig = aog_panel(PANEL_LONG, PANEL_MONTHLY)
    axs = [b for b in fig.content if b isa Axis]
    @test length(axs) == 2
    bytitle(t) = only(a for a in axs if a.title[] == t)
    @testset "labels" begin
        daily = bytitle("Daily temperature")
        @test (daily.xlabel[], daily.ylabel[]) == ("Day of year", "Temperature (°C)")
        monthly = bytitle("Monthly mean")
        @test (monthly.xlabel[], monthly.ylabel[]) == ("Month", "Mean temperature (°C)")
    end
    @testset "colour per city" begin
        ls = [p for a in axs for p in a.scene.plots if p isa Lines]
        @test length(ls) == 2
        @test allunique([p.color[] for p in ls])
        @test isapprox([q[1] for q in ls[1][1][]], [31, 34]; atol = 0, rtol = 0)   # lisbon
    end
    @testset "legend" begin
        leg = only(b for b in fig.content if b isa Legend)
        (title, entries) = only(leg.entrygroups[])
        @test title == "City"
        @test [e.label[] for e in entries] == ["lisbon", "vienna"]
    end
end
