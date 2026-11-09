"""
    Figures

Reference solution of the `figures` guided project: read a wide table of
daily temperatures, reshape and summarise it, and draw the same report panel
with CairoMakie, AlgebraOfGraphics, Plots.jl and Gadfly.
"""
module Figures

using DataFrames, Dates, Statistics
using CairoMakie
import AlgebraOfGraphics as AoG
import Plots
import Gadfly

export read_wide, long_format, monthly_means, makie_panel, aog_panel, plots_panel, gadfly_panel, save_all

# Titles and axis labels shared by every version of the panel.
const DAILY_TITLE = "Daily temperature"
const MONTHLY_TITLE = "Monthly mean"
const DAY_LABEL = "Day of year"
const TEMP_LABEL = "Temperature (°C)"
const MONTH_LABEL = "Month"
const MEAN_LABEL = "Mean temperature (°C)"
const CITY_LABEL = "City"

# ---- milestone 1: data preparation ------------------------------------------------------

"""A field of the wide file: empty means missing, anything else is a number."""
parse_value(s::AbstractString) = isempty(strip(s)) ? missing : parse(Float64, s)

"""
    read_wide(io::IO) -> DataFrame

Read the wide CSV text: a header `date,<city>,<city>,...`, then one line per
day. Column `date` holds `Date`s; each city column holds
`Union{Missing, Float64}` values, `missing` for an empty field.
"""
function read_wide(io::IO)
    lines = [strip(l) for l in eachline(io) if !isempty(strip(l))]
    header = String.(strip.(split(lines[1], ',')))
    rows = [split(l, ',') for l in lines[2:end]]
    df = DataFrame(date = [Date(r[1]) for r in rows])
    for (j, name) in enumerate(header[2:end])
        df[!, name] = Union{Missing, Float64}[parse_value(r[j + 1]) for r in rows]
    end
    return df
end

"""
    long_format(wide::DataFrame) -> DataFrame

One row per non-missing value of the wide table: columns `date`, `city`
(`String`), `temp` (`Float64`), sorted by city, then date.
"""
function long_format(wide::DataFrame)
    t = stack(wide, Not(:date); variable_name = :city, value_name = :temp)
    t = dropmissing(t, :temp)
    t.city = String.(t.city)
    return sort!(select(t, :date, :city, :temp), [:city, :date])
end

"""Mean of the values that are present (missing ones are skipped)."""
mean_present(v) = mean(skipmissing(v))

"""
    monthly_means(long::DataFrame) -> DataFrame

One row per city and month: columns `city`, `month` (`Int`, 1 to 12) and
`mean_temp`, the mean of the non-missing temperatures; sorted by city, then
month.
"""
function monthly_means(long::DataFrame)
    t = transform(long, :date => ByRow(month) => :month)
    s = combine(groupby(t, [:city, :month]), :temp => mean_present => :mean_temp)
    return sort!(s, [:city, :month])
end

# ---- milestone 2: Makie --------------------------------------------------------------------

"""Position of each entry of `names` in the sorted list of its distinct values."""
city_index(names) = (cities = sort(unique(names)); [findfirst(==(c), cities) for c in names])

"""
    makie_panel(long, monthly) -> Figure

Two axes side by side: daily temperatures (one line per city) and monthly
means (bars dodged by city), with a legend in the third column.
"""
function makie_panel(long::DataFrame, monthly::DataFrame)
    fig = Figure(size = (900, 350))
    ax1 = Axis(fig[1, 1]; title = DAILY_TITLE, xlabel = DAY_LABEL, ylabel = TEMP_LABEL)
    for g in groupby(sort(long, [:city, :date]), :city; sort = true)
        lines!(ax1, day.(g.date), g.temp; label = first(g.city))
    end
    ax2 = Axis(fig[1, 2]; title = MONTHLY_TITLE, xlabel = MONTH_LABEL, ylabel = MEAN_LABEL)
    idx = city_index(monthly.city)
    barplot!(ax2, monthly.month, monthly.mean_temp; dodge = idx, color = Makie.wong_colors()[idx])
    Legend(fig[1, 3], ax1, CITY_LABEL)
    return fig
end

# ---- milestone 3: AlgebraOfGraphics --------------------------------------------------------

"""
    aog_panel(long, monthly) -> Figure

The same two panels, each one AlgebraOfGraphics specification drawn into a
cell of one figure, and the legend AlgebraOfGraphics derives from the colour
mapping.
"""
function aog_panel(long::DataFrame, monthly::DataFrame)
    fig = Figure(size = (900, 350))
    daily = AoG.data(long) *
            AoG.mapping(:date => dayofyear => DAY_LABEL, :temp => TEMP_LABEL, color = :city => CITY_LABEL) *
            AoG.visual(Lines)
    grid = AoG.draw!(fig[1, 1], daily; axis = (; title = DAILY_TITLE))
    bars = AoG.data(monthly) *
           AoG.mapping(:month => MONTH_LABEL, :mean_temp => MEAN_LABEL, color = :city => CITY_LABEL, dodge = :city) *
           AoG.visual(BarPlot)
    AoG.draw!(fig[1, 2], bars; axis = (; title = MONTHLY_TITLE))
    AoG.legend!(fig[1, 3], grid)
    return fig
end

# ---- milestone 4: Plots.jl, Gadfly and SVG files -------------------------------------------

"""
    plots_panel(long) -> Plots.Plot

The daily panel in Plots.jl: one series per city, labelled with its name.
"""
function plots_panel(long::DataFrame)
    t = sort(long, [:city, :date])
    return Plots.plot(dayofyear.(t.date), t.temp; group = t.city,
                      title = DAILY_TITLE, xlabel = DAY_LABEL, ylabel = TEMP_LABEL)
end

"""
    gadfly_panel(long) -> Gadfly.Plot

The daily panel in Gadfly: colour maps to city.
"""
function gadfly_panel(long::DataFrame)
    t = transform(sort(long, [:city, :date]), :date => ByRow(dayofyear) => :day)
    return Gadfly.plot(t, x = :day, y = :temp, color = :city, Gadfly.Geom.line,
                       Gadfly.Guide.title(DAILY_TITLE), Gadfly.Guide.xlabel(DAY_LABEL),
                       Gadfly.Guide.ylabel(TEMP_LABEL), Gadfly.Guide.colorkey(title = CITY_LABEL))
end

const FILE_NAMES = ("makie.svg", "aog.svg", "plots.svg", "gadfly.svg")

"""
    save_all(dir, long, monthly) -> Vector{String}

Write makie.svg, aog.svg, plots.svg and gadfly.svg into `dir`; return their
paths, sorted.
"""
function save_all(dir::AbstractString, long::DataFrame, monthly::DataFrame)
    paths = [joinpath(dir, n) for n in FILE_NAMES]
    save(paths[1], makie_panel(long, monthly))
    save(paths[2], aog_panel(long, monthly))
    Plots.savefig(plots_panel(long), paths[3])
    Gadfly.draw(Gadfly.SVG(paths[4], 16 * Gadfly.cm, 9 * Gadfly.cm), gadfly_panel(long))
    return sort(paths)
end

end # module Figures
