"""
    Tidy

Reference solution of the `tidy` guided project: read a messy sensor CSV,
clean it, summarise it per site and day, and write the summary back out.
"""
module Tidy

using CSV, DataFrames, Dates, Statistics

export read_readings, clean, summarize, write_summary, read_summary

# ---- milestone 1: reading ------------------------------------------------------------

const MISSING_MARKERS = ["NA", "", "-"]
const TIME_FORMAT = dateformat"yyyy-mm-dd HH:MM"
const COLUMN_TYPES = Dict(:site => String, :time => DateTime, :temp => Float64,
                          :unit => String, :humidity => Float64)

"""
    read_readings(io::IO) -> DataFrame
    read_readings(path::AbstractString) -> DataFrame

Read sensor readings with columns `site`, `time`, `temp`, `unit`, `humidity`.
`NA`, an empty field and `-` mean missing; times are `yyyy-mm-dd HH:MM`.
"""
function read_readings(io::IO)
    return CSV.read(io, DataFrame; missingstring = MISSING_MARKERS, types = COLUMN_TYPES,
                    dateformat = TIME_FORMAT, stringtype = String)
end

read_readings(path::AbstractString) = open(read_readings, path)

# ---- milestone 2: cleaning -----------------------------------------------------------

const TEMP_RANGE = (-50.0, 60.0)       # °C a sensor can plausibly report
const HUMIDITY_RANGE = (0.0, 100.0)    # percent

normalize_site(s::AbstractString) = lowercase(strip(s))

"""Degrees Fahrenheit to Celsius (`missing` stays `missing`)."""
to_celsius(t) = (t - 32) * 5 / 9

inrange(x, (lo, hi)) = lo <= x <= hi

"""
    is_valid(temp, humidity) -> Bool

A reading is valid when its temperature is present and in `TEMP_RANGE`, and
its humidity is missing or in `HUMIDITY_RANGE`.
"""
is_valid(temp, humidity) = !ismissing(temp) && inrange(temp, TEMP_RANGE) &&
                           (ismissing(humidity) || inrange(humidity, HUMIDITY_RANGE))

"""
    clean(df::DataFrame) -> DataFrame

A new table (the input is not changed): site names stripped and lower-cased,
Fahrenheit readings converted to Celsius (unit `"C"`), exact duplicate rows
after that removed (first kept, order kept), and a `valid` column.
"""
function clean(df::DataFrame)
    out = copy(df)
    out.site = normalize_site.(out.site)
    isf = out.unit .== "F"
    out.temp = ifelse.(isf, to_celsius.(out.temp), out.temp)
    out.unit = ifelse.(isf, "C", out.unit)
    unique!(out)
    out.valid = is_valid.(out.temp, out.humidity)
    return out
end

# ---- milestone 3: summarising ---------------------------------------------------------

"""Mean of the non-missing values, `missing` when there are none."""
mean_present(v) = (x = collect(skipmissing(v)); isempty(x) ? missing : mean(x))

"""
    summarize(df::DataFrame) -> DataFrame

One row per site and calendar day over the valid rows of a cleaned table:
`site`, `date`, `n`, `mean_temp`, `max_temp`, `mean_humidity` (`missing` when
the day has no humidity), sorted by site, then date.
"""
function summarize(df::DataFrame)
    v = df[df.valid, :]
    v.date = Date.(v.time)
    s = combine(groupby(v, [:site, :date]), nrow => :n, :temp => mean => :mean_temp,
                :temp => maximum => :max_temp, :humidity => mean_present => :mean_humidity)
    return sort!(s, [:site, :date])
end

# ---- milestone 4: writing and reading back ---------------------------------------------

const DIGITS = 2

"""
    write_summary(io::IO, s::DataFrame)

Write a summary as CSV: a header, ISO dates, numbers rounded to 2 decimals,
`NA` for missing.
"""
function write_summary(io::IO, s::DataFrame)
    out = transform(s, [:mean_temp, :max_temp, :mean_humidity] .=> ByRow(x -> round(x; digits = DIGITS)); renamecols = false)
    CSV.write(io, out; missingstring = "NA")
    return nothing
end

"""
    read_summary(io::IO) -> DataFrame

Read what `write_summary` wrote, with the same column types.
"""
function read_summary(io::IO)
    return CSV.read(io, DataFrame; missingstring = "NA", stringtype = String,
                    types = Dict(:site => String, :date => Date, :n => Int, :mean_temp => Float64,
                                 :max_temp => Float64, :mean_humidity => Float64))
end

end # module Tidy
