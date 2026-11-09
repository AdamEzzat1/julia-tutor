# A student's package at milestone 1: correct data preparation.
module Figures

using DataFrames, Dates, Statistics

export read_wide, long_format, monthly_means

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

end # module Figures
